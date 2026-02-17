import { Clipboard, getSelectedText, showHUD, showToast, Toast } from "@raycast/api";
import { optimize } from "./api";

export default async function QuickOptimizeCommand() {
  let text: string;

  try {
    text = await getSelectedText();
  } catch {
    await showToast({
      style: Toast.Style.Failure,
      title: "No text selected",
      message: "Select some text before running Quick Optimize.",
    });
    return;
  }

  if (!text.trim()) {
    await showToast({
      style: Toast.Style.Failure,
      title: "Selected text is empty",
    });
    return;
  }

  try {
    const result = await optimize({ text });
    await Clipboard.copy(result.output);
    await showHUD("Optimized prompt copied to clipboard");
  } catch (err) {
    await showToast({
      style: Toast.Style.Failure,
      title: "Optimization failed",
      message: err instanceof Error ? err.message : String(err),
    });
  }
}
