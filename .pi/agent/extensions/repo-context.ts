/**
 * Repo context reminder that provides project instructions and advertises
 * available skills when working with multiple repos.
 *
 * Pi resolves context files (AGENTS.md / CLAUDE.md) and skills once, for the
 * directory it was started in. When the agent modifies files elsewhere (a
 * sibling repo, or a subdirectory with its own AGENTS.md), this extension asks
 * Pi's own `DefaultResourceLoader` what it would load if started in that
 * directory, and tells the model about anything not already in its system
 * prompt. Discovery rules and project trust therefore match Pi exactly;
 * resources of untrusted projects are never announced.
 *
 * The reminder is delivered as a steering custom message (user role) rather
 * than inside the tool result, so the model does not dismiss it as a prompt
 * injection from file content. Reading files elsewhere announces nothing; the
 * first `write` / `edit` into a new context is blocked so the model reviews the
 * instructions before modifying files.
 *
 * Each context file and skill is announced once. Compaction resets the
 * announced set because a summary may drop the reminder.
 */

import { existsSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";

import {
  CustomMessageComponent,
  DefaultResourceLoader,
  type ExtensionAPI,
  type ExtensionContext,
  formatSkillsForPrompt,
  getAgentDir,
  hasTrustRequiringProjectResources,
  type MessageRenderer,
  ProjectTrustStore,
  SettingsManager,
  type Skill,
  type ToolCallEvent,
  type ToolCallEventResult,
} from "@earendil-works/pi-coding-agent";

/** Custom message type for injected reminders. */
const MESSAGE_TYPE = "repo-context";

/** Tools that modify files; their first call into a new context is blocked. */
const WRITE_TOOLS = new Set(["write", "edit"]);

interface ContextFile {
  path: string;
  content: string;
}

/** Resources Pi would load when started in a given directory. */
interface DirResources {
  contextFiles: ContextFile[];
  skills: Skill[];
}

/** Resolve a tool path argument the way Pi's file tools do (`@` prefix, `~`, cwd-relative). */
function resolveToolPath(rawPath: string, cwd: string): string {
  const path = rawPath.startsWith("@") ? rawPath.slice(1) : rawPath;
  if (path === "~" || path.startsWith("~/"))
    return join(homedir(), path.slice(1));
  return resolve(cwd, path);
}

/** Return the closest existing directory for a file or directory path. */
function nearestExistingDir(path: string): string {
  let current = path;
  while (!existsSync(current)) current = dirname(current);
  return statSync(current).isDirectory() ? current : dirname(current);
}

/**
 * Decide project trust for `dir` without prompting, mirroring Pi's startup:
 * a saved decision wins, projects without trust-requiring resources are
 * trusted, and otherwise only `defaultProjectTrust: "always"` trusts.
 */
function isTrusted(
  dir: string,
  trustStore: ProjectTrustStore,
  settings: SettingsManager,
): boolean {
  const saved = trustStore.get(dir);
  if (saved !== null) return saved;
  if (!hasTrustRequiringProjectResources(dir)) return true;
  return settings.getDefaultProjectTrust() === "always";
}

/** Load the context files and skills Pi would use with `dir` as its cwt. */
async function loadDirResources(
  dir: string,
  agentDir: string,
  trustStore: ProjectTrustStore,
): Promise<DirResources> {
  const probe = SettingsManager.create(dir, agentDir, {
    projectTrusted: false,
  });
  const settingsManager = SettingsManager.create(dir, agentDir, {
    projectTrusted: isTrusted(dir, trustStore, probe),
  });
  const loader = new DefaultResourceLoader({
    cwd: dir,
    agentDir,
    settingsManager,
    noExtensions: true,
  });
  await loader.reload();
  return {
    contextFiles: loader.getAgentsFiles().agentsFiles,
    skills: loader.getSkills().skills,
  };
}

/** Advertise instruction file paths and skill metadata without loading directives. */
function formatReminder(dir: string, resources: DirResources): string {
  // Keep Pi's skill metadata format, but omit its introductory loading instructions.
  const skills = formatSkillsForPrompt(resources.skills).trim();
  const skillCatalog = skills
    ? skills.slice(skills.indexOf("<available_skills>"))
    : "";
  const files = resources.contextFiles.map((file) => `- ${file.path}`);
  return [
    `You are accessing ${dir}, whose project instructions and skills are not in your system prompt.`,
    files.length > 0
      ? `<project_context>\nProject instruction files are available at these paths. Decide whether to read them based on the task:\n\n${files.join("\n")}\n</project_context>`
      : "",
    skillCatalog
      ? `<skills>\nThe following skills are available (metadata only).\n\n${skillCatalog}\n</skills>`
      : "",
  ]
    .filter(Boolean)
    .join("\n\n");
}

/**
 * Tracks which context files and skills the model already knows about and
 * computes the not-yet-announced resources for directories touched by tools.
 */
class RepoContextTracker {
  private readonly agentDir = getAgentDir();
  private readonly trustStore = new ProjectTrustStore(this.agentDir);
  /** Resource lookups per directory; trust and files rarely change within a session. */
  private readonly cache = new Map<string, Promise<DirResources>>();
  /** Paths loaded by Pi itself into the system prompt. */
  private readonly loaded = new Set<string>();
  /** Paths this tracker has already announced to the model. */
  private readonly announced = new Set<string>();

  /** Record what Pi put into the system prompt for this run. */
  setLoaded(contextFiles: ContextFile[], skills: Skill[]): void {
    this.loaded.clear();
    for (const file of contextFiles) this.loaded.add(file.path);
    for (const skill of skills) this.loaded.add(skill.filePath);
  }

  /** Forget announcements, e.g. after compaction may have dropped them. */
  resetAnnounced(): void {
    this.announced.clear();
  }

  /**
   * Return resources for `dir` that the model has not seen yet, and mark them
   * as announced. Returns undefined when there is nothing new.
   */
  async takeFresh(dir: string): Promise<DirResources | undefined> {
    let pending = this.cache.get(dir);
    if (!pending) {
      pending = loadDirResources(dir, this.agentDir, this.trustStore);
      this.cache.set(dir, pending);
    }
    const all = await pending;
    const isNew = (path: string) =>
      !this.loaded.has(path) && !this.announced.has(path);
    const fresh: DirResources = {
      contextFiles: all.contextFiles.filter((file) => isNew(file.path)),
      skills: all.skills.filter((skill) => isNew(skill.filePath)),
    };
    if (fresh.contextFiles.length === 0 && fresh.skills.length === 0) return;

    for (const file of fresh.contextFiles) this.announced.add(file.path);
    for (const skill of fresh.skills) this.announced.add(skill.filePath);
    return fresh;
  }
}

/**
 * Announce new repo context for a write or edit, and block that first call so
 * the model sees the instructions before modifying files.
 */
async function handleToolCall(
  pi: ExtensionAPI,
  tracker: RepoContextTracker,
  event: ToolCallEvent,
  ctx: ExtensionContext,
): Promise<ToolCallEventResult | undefined> {
  if (!WRITE_TOOLS.has(event.toolName)) return;

  const rawPath = (event.input as { path?: unknown }).path;
  const dir = nearestExistingDir(
    resolveToolPath(typeof rawPath === "string" ? rawPath : ".", ctx.cwd),
  );
  const fresh = await tracker.takeFresh(dir);
  if (!fresh) return;

  pi.sendMessage(
    {
      customType: MESSAGE_TYPE,
      content: formatReminder(dir, fresh),
      display: true,
    },
    { deliverAs: "steer" },
  );

  return {
    block: true,
    reason: `Not applied yet: project context references for ${dir} are delivered in the next message. Consider which references are relevant, then retry this ${event.toolName}. Reading the referenced files is your decision.`,
  };
}

/** Fold the reminder in the TUI without changing its model-visible content. */
const foldableRepoContextRenderer: MessageRenderer = (message, options) => {
  // Returning undefined delegates the expanded view to Pi's default renderer.
  if (options.expanded) return;

  const content =
    typeof message.content === "string"
      ? message.content
      : message.content
          .filter((block) => block.type === "text")
          .map((block) => block.text)
          .join("\n");
  if (!content.includes("\n")) return;

  const preview = content.split("\n", 1)[0];
  const hint = options.keyHint("app.tools.expand", "to expand");

  return new CustomMessageComponent(
    { ...message, content: `${preview}\n\n(${hint})` },
    undefined,
    undefined,
    options.outputPad,
  );
};

export default function repoContext(pi: ExtensionAPI): void {
  const tracker = new RepoContextTracker();

  pi.registerMessageRenderer(MESSAGE_TYPE, foldableRepoContextRenderer);

  pi.on("before_agent_start", ({ systemPromptOptions: opts }) =>
    tracker.setLoaded(opts.contextFiles, opts.skills),
  );
  pi.on("session_compact", () => tracker.resetAnnounced());
  pi.on("tool_call", (event, ctx) => handleToolCall(pi, tracker, event, ctx));
}
