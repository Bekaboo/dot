import type { Plugin } from "@opencode-ai/plugin";

const HEADING_RE = /^(#{1,6})\s+(.*)$/;

function checkMd(content: string, filePath: string): string[] {
  const issues: string[] = [];
  const lines = content.split("\n");

  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(HEADING_RE);
    if (!m) continue;

    const level = m[1];
    const title = m[2];

    if (/^\d+\.\s/.test(title)) {
      issues.push(`${filePath}:${i + 1}: numbered heading "${title.trim()}"`);
    }

    if (i + 1 < lines.length && lines[i + 1] !== "") {
      issues.push(
        `${filePath}:${i + 1}: missing blank line after "${level} ${title}"`,
      );
    }
  }

  return issues;
}

export const MdLintPlugin: Plugin = async ({ client }) => {
  return {
    "tool.execute.after": async (input, _output) => {
      if (input.tool !== "write" && input.tool !== "edit") return;
      const fp: string | undefined = input.args?.filePath;
      if (!fp || !fp.endsWith(".md")) return;

      let content: string | null = null;

      if (input.tool === "write" && input.args?.content) {
        content = input.args.content as string;
      } else {
        try {
          content = await Bun.file(fp).text();
        } catch {
          return;
        }
      }

      if (!content) return;

      const issues = checkMd(content, fp);
      if (issues.length === 0) return;

      await client.app.log({
        body: {
          service: "md-lint",
          level: "warn",
          message: issues.join("\n"),
        },
      });
    },
  };
};
