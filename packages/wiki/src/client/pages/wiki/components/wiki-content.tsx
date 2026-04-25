/**
 * @file Central content area: Markdown rendering with source badges.
 *
 * Environment-specific behavior (link rendering, source badges, i18n)
 * is injected via WikiContentEnvProvider. The host environment must
 * wrap this component in that provider.
 */

import { useCallback } from "react";
import ReactMarkdown, { defaultUrlTransform } from "react-markdown";
import remarkGfm from "remark-gfm";
import rehypeSlug from "rehype-slug";
import { MermaidDiagram } from "@indexion/mermaid-viewer";
import { KgfCodeBlock } from "@indexion/syntax-highlight";
import { useBranding } from "../../../lib/branding-context.tsx";
import { useWikiContentEnv } from "./wiki-content-context.tsx";
import type { WikiPage } from "@indexion/api-client";

type Props = {
  readonly page: WikiPage;
};

export const WikiContent = ({ page }: Props): React.JSX.Element => {
  const env = useWikiContentEnv();
  const { colorScheme } = useBranding();

  const renderPre = useCallback(
    (
      props: React.HTMLAttributes<HTMLPreElement> & {
        children?: React.ReactNode;
      },
    ) => {
      const child = Array.isArray(props.children)
        ? props.children[0]
        : props.children;
      const isMermaid =
        child != null &&
        typeof child === "object" &&
        "props" in child &&
        /language-mermaid/.test(child.props?.className ?? "");
      if (isMermaid) {
        // Mermaid handles its own container — render children directly without <pre> wrapper
        return <>{props.children}</>;
      }
      return (
        <pre {...props} className="overflow-x-auto rounded-lg bg-muted p-4">
          {props.children}
        </pre>
      );
    },
    [],
  );

  const renderCode = useCallback(
    (
      props: React.HTMLAttributes<HTMLElement> & {
        children?: React.ReactNode;
        className?: string;
      },
    ) => {
      const match = /language-mermaid/.exec(props.className ?? "");
      if (match) {
        const code = String(props.children).replace(/\n$/, "");
        return <MermaidDiagram code={code} className="my-4" />;
      }
      return <KgfCodeBlock {...props} colorScheme={colorScheme} />;
    },
    [colorScheme],
  );

  const urlTransform = useCallback(
    (url: string) =>
      url.startsWith("wiki://") ? url : defaultUrlTransform(url),
    [],
  );

  const renderLink = useCallback(
    (
      props: React.AnchorHTMLAttributes<HTMLAnchorElement> & {
        node?: unknown;
      },
    ) => {
      const { node: _node, ...rest } = props;
      const href = rest.href ?? "";
      if (href.startsWith("wiki://")) {
        const pageId = href.slice(7);
        return env.renderWikiLink(pageId, rest.children);
      }
      return <a {...rest} />;
    },
    [env],
  );

  return (
    <article className="mx-auto w-full max-w-3xl px-4 py-4 md:px-8 md:py-6">
      {page.sources.length > 0 && (
        <details className="mb-4">
          <summary className="cursor-pointer text-xs text-muted-foreground">
            {env.sourceFilesLabel}
          </summary>
          <div className="mt-2 flex flex-wrap gap-2">
            {page.sources.map((src) => (
              <span key={src.file}>{env.renderSourceBadge(src)}</span>
            ))}
          </div>
        </details>
      )}

      <div className="prose dark:prose-invert max-w-none prose-headings:scroll-mt-16 prose-pre:p-0 prose-pre:bg-transparent">
        <ReactMarkdown
          remarkPlugins={[remarkGfm]}
          rehypePlugins={[rehypeSlug]}
          urlTransform={urlTransform}
          components={{ pre: renderPre, a: renderLink, code: renderCode }}
        >
          {page.content}
        </ReactMarkdown>
      </div>

      {env.relatedPagesLabel !== null && page.children.length > 0 && (
        <nav className="mt-6 border-t pt-4">
          <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
            {env.relatedPagesLabel}
          </h3>
          <ul className="flex flex-wrap gap-2">
            {page.children.map((childId) => (
              <li key={childId}>{env.renderWikiLink(childId, childId)}</li>
            ))}
          </ul>
        </nav>
      )}
    </article>
  );
};
