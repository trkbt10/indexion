/**
 * @file Central content area: Markdown rendering with source badges.
 */

import { useCallback } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import rehypeSlug from "rehype-slug";
import rehypeHighlight from "rehype-highlight";
import { Link } from "react-router";
import { ScrollArea } from "../../../components/ui/scroll-area.tsx";
import { MermaidDiagram } from "../../../components/shared/mermaid-diagram.tsx";
import { SourceBadge } from "./source-badge.tsx";
import type { WikiPage } from "@indexion/api-client";

type Props = {
  readonly page: WikiPage;
};

export const WikiContent = ({ page }: Props): React.JSX.Element => {
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
      return <code {...props} />;
    },
    [],
  );

  const renderLink = useCallback(
    (props: React.AnchorHTMLAttributes<HTMLAnchorElement>) => {
      const href = props.href ?? "";
      if (href.startsWith("wiki://")) {
        const pageId = href.slice(7);
        return <Link to={`/wiki/${pageId}`}>{props.children}</Link>;
      }
      return <a {...props} />;
    },
    [],
  );

  return (
    <ScrollArea className="h-full">
      <article className="mx-auto max-w-3xl px-8 py-6">
        {page.sources.length > 0 && (
          <details className="mb-4">
            <summary className="cursor-pointer text-xs text-muted-foreground">
              Relevant source files
            </summary>
            <div className="mt-2 flex flex-wrap gap-2">
              {page.sources.map((src) => (
                <SourceBadge key={src.file} source={src} />
              ))}
            </div>
          </details>
        )}

        <div className="prose prose-invert max-w-none prose-headings:scroll-mt-16 prose-pre:bg-muted prose-code:text-sm">
          <ReactMarkdown
            remarkPlugins={[remarkGfm]}
            rehypePlugins={[rehypeSlug, rehypeHighlight]}
            components={{ a: renderLink, code: renderCode }}
          >
            {page.content}
          </ReactMarkdown>
        </div>
      </article>
    </ScrollArea>
  );
};
