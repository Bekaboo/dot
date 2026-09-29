import type { Plugin } from "@opencode-ai/plugin";

const configPath = `${process.env.HOME}/.markdownlint-cli2.cjs`;

export const MdLintPlugin: Plugin = async ({ client }) => ({
  "tool.execute.after": async (input, output) => {
    if (input.tool !== "write" && input.tool !== "edit") return;

    const filePath: string | undefined = input.args?.filePath;
    if (!filePath?.endsWith(".md")) return;

    let before: string;
    try {
      before = await Bun.file(filePath).text();
    } catch {
      return;
    }

    const process = Bun.spawn(
      ["markdownlint-cli2", "--config", configPath, "--fix", filePath],
      { stdout: "pipe", stderr: "pipe" },
    );
    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(process.stdout).text(),
      new Response(process.stderr).text(),
      process.exited,
    ]);

    const after = await Bun.file(filePath).text();
    const details = [stdout, stderr].filter(Boolean).join("\n").trim();

    let feedback = "";
    if (before !== after) {
      feedback =
        "markdownlint-cli2 automatically fixed Markdown formatting. Review the updated file before finishing.";
    } else if (exitCode !== 0) {
      feedback = `markdownlint-cli2 found unresolved issues:\n${details}`;
    }

    if (!feedback) return;
    output.output = `${output.output}\n\n${feedback}`;

    await client.app.log({
      body: {
        service: "md-lint",
        level: exitCode === 0 ? "info" : "warn",
        message: feedback,
      },
    });
  },
});
