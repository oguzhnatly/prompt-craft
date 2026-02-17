import {
  Action,
  ActionPanel,
  Detail,
  Form,
  showToast,
  Toast,
  useNavigation,
} from "@raycast/api";
import { useEffect, useState } from "react";
import { getStyles, optimize, StyleInfo } from "./api";

export default function OptimizeCommand() {
  const [styles, setStyles] = useState<StyleInfo[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const { push } = useNavigation();

  useEffect(() => {
    getStyles()
      .then((s) => {
        setStyles(s);
        setIsLoading(false);
      })
      .catch((err) => {
        showToast({
          style: Toast.Style.Failure,
          title: "PromptCraft not reachable",
          message: err.message,
        });
        setIsLoading(false);
      });
  }, []);

  async function handleSubmit(values: {
    text: string;
    styleId: string;
    verbosity: string;
  }) {
    if (!values.text.trim()) {
      showToast({ style: Toast.Style.Failure, title: "Prompt text is required" });
      return;
    }

    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Optimizing...",
    });

    try {
      const result = await optimize({
        text: values.text,
        styleId: values.styleId || undefined,
        verbosity: (values.verbosity as "concise" | "balanced" | "detailed") || undefined,
      });

      toast.hide();

      push(
        <Detail
          markdown={`# Optimized Prompt\n\n${result.output}\n\n---\n\n*${result.style} | ${result.provider} (${result.model}) | ${result.durationMs}ms | ${result.tier}*`}
          actions={
            <ActionPanel>
              <Action.CopyToClipboard title="Copy to Clipboard" content={result.output} />
              <Action.Paste title="Paste" content={result.output} />
            </ActionPanel>
          }
        />
      );
    } catch (err) {
      toast.style = Toast.Style.Failure;
      toast.title = "Optimization failed";
      toast.message = err instanceof Error ? err.message : String(err);
    }
  }

  return (
    <Form
      isLoading={isLoading}
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Optimize" onSubmit={handleSubmit} />
        </ActionPanel>
      }
    >
      <Form.TextArea id="text" title="Prompt" placeholder="Enter the prompt to optimize..." />
      <Form.Dropdown id="styleId" title="Style" defaultValue="">
        <Form.Dropdown.Item value="" title="Default" />
        {styles.map((s) => (
          <Form.Dropdown.Item key={s.id} value={s.id} title={s.name} />
        ))}
      </Form.Dropdown>
      <Form.Dropdown id="verbosity" title="Verbosity" defaultValue="">
        <Form.Dropdown.Item value="" title="Default" />
        <Form.Dropdown.Item value="concise" title="Concise" />
        <Form.Dropdown.Item value="balanced" title="Balanced" />
        <Form.Dropdown.Item value="detailed" title="Detailed" />
      </Form.Dropdown>
    </Form>
  );
}
