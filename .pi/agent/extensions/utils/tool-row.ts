/**
 * Pieces of a one-line tool call row, shared by the extensions whose arguments
 * carry long text.
 *
 * Pi's default row prints every argument as `key=value` and wraps its `Text`,
 * so one long command, prompt or report takes over the transcript. These
 * helpers keep such a row on a single line and leave the full arguments to the
 * expanded row to make the UI prettier.
 */

import type { AgentToolResult, Theme } from "@earendil-works/pi-coding-agent";
import type { Component } from "@earendil-works/pi-tui";
import { truncateKeepingBackground } from "./ansi.ts";

/**
 * One tool row line, truncated to the row width instead of wrapped.
 */
export class OneLine implements Component {
  private readonly text: string;

  constructor(text: string) {
    this.text = text;
  }

  /**
   * @param width - Row width in cells.
   * @returns The single truncated line, with the block's background kept.
   */
  render(width: number): string[] {
    return [truncateKeepingBackground(this.text, width)];
  }

  /** Nothing is cached, so there is nothing to drop. */
  invalidate(): void {}
}

/**
 * First line of a multi-line argument, such as a command or a prompt.
 *
 * @param text - Argument value.
 * @returns Its first line, trimmed.
 */
export function firstLine(text: string): string {
  return text.split("\n", 1)[0].trim();
}

/**
 * Header of a tool row: the tool name and the job or subagent id it acts on.
 *
 * @param name - Tool name.
 * @param id - Id from the call, absent while the call streams in or when the
 *   call acts on everything.
 * @param theme - Active theme.
 * @returns Styled one-line header.
 */
export function toolRowHeader(
  name: string,
  id: string | undefined,
  theme: Theme,
): string {
  const parts = [theme.fg("toolTitle", theme.bold(name))];
  if (id) parts.push(theme.fg("accent", id));
  return parts.join(" ");
}

/**
 * Arguments of an expanded call row, one key per line.
 *
 * @param args - Call arguments.
 * @param theme - Active theme.
 * @returns One styled line per argument, a multi-line value indented under its
 *   key.
 */
export function expandedArgs(args: object, theme: Theme): string[] {
  return Object.entries(args).flatMap(([key, value]) => {
    const text = typeof value === "string" ? value : JSON.stringify(value);
    const [head, ...rest] = text.split("\n");
    return [
      theme.fg("muted", `  ${key}: ${head}`),
      ...rest.map((line) => theme.fg("muted", `    ${line}`)),
    ];
  });
}

/**
 * Text of a tool result, as the model received it.
 *
 * @param result - Result whose text parts are joined.
 * @returns The joined text, or the empty string for a result without one.
 */
export function resultText(result: AgentToolResult<unknown>): string {
  return result.content
    .filter((part) => part.type === "text")
    .map((part) => part.text)
    .join("\n");
}
