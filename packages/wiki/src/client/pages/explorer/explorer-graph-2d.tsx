import { useMemo } from "react";
import type { CodeGraph, IndexedFunction } from "@indexion/api-client";
import { buildTree } from "../graph/graph-data.ts";
import type { GraphTree, FolderNode } from "../graph/graph-types.ts";
import { MermaidDiagram } from "../../components/shared/mermaid-diagram.tsx";
import { ScrollArea } from "../../components/ui/scroll-area.tsx";

type Props = {
  readonly graph: CodeGraph;
  readonly indexFns: ReadonlyArray<IndexedFunction>;
};

/**
 * LOD: collapse leaf nodes under a common parent when there are too many.
 * Returns a pruned set of nodes and edges suitable for readable mermaid output.
 */
const pruneTree = (tree: GraphTree, maxNodes: number): GraphTree => {
  const { nodes, edges, roots } = tree;
  if (nodes.size <= maxNodes) {
    return tree;
  }

  // Keep only non-leaf nodes (containers with children) + top N leaf nodes by edge count
  const edgeCount = new Map<string, number>();
  for (const e of edges) {
    edgeCount.set(e.from, (edgeCount.get(e.from) ?? 0) + 1);
    edgeCount.set(e.to, (edgeCount.get(e.to) ?? 0) + 1);
  }

  const containers = new Map<string, FolderNode>();
  const leaves: Array<[string, FolderNode, number]> = [];
  for (const [id, node] of nodes) {
    if (node.children.length > 0) {
      containers.set(id, node);
    } else {
      leaves.push([id, node, edgeCount.get(id) ?? 0]);
    }
  }

  // Sort leaves by connectivity, keep top ones
  leaves.sort((a, b) => b[2] - a[2]);
  const budget = Math.max(maxNodes - containers.size, 10);
  const kept = new Set<string>([...containers.keys()]);
  for (let i = 0; i < Math.min(budget, leaves.length); i++) {
    kept.add(leaves[i][0]);
  }

  const prunedNodes = new Map<string, FolderNode>();
  for (const id of kept) {
    prunedNodes.set(id, nodes.get(id)!);
  }

  const prunedEdges = edges.filter((e) => kept.has(e.from) && kept.has(e.to));

  return { nodes: prunedNodes, edges: prunedEdges, roots };
};

/** Build mermaid code from a GraphTree, using module paths as labels. */
const treeToMermaid = (tree: GraphTree): string => {
  const paths = [...tree.nodes.keys()];

  // Find longest common prefix to shorten labels
  const commonPrefix = (() => {
    if (paths.length === 0) {
      return "";
    }
    const first = paths[0].split("/");
    let len = first.length;
    for (let i = 1; i < paths.length; i++) {
      const parts = paths[i].split("/");
      len = Math.min(len, parts.length);
      for (let j = 0; j < len; j++) {
        if (parts[j] !== first[j]) {
          len = j;
          break;
        }
      }
    }
    return len > 0 ? first.slice(0, len).join("/") + "/" : "";
  })();

  const nodeIds = new Map<string, string>();
  let idx = 0;
  for (const id of paths) {
    nodeIds.set(id, `N${idx++}`);
  }

  const lines: string[] = ["graph LR"];
  for (const [id] of tree.nodes) {
    const nid = nodeIds.get(id)!;
    // Use path relative to common prefix for readability
    const label = (commonPrefix ? id.slice(commonPrefix.length) : id).replace(
      /"/g,
      "#quot;",
    );
    lines.push(`  ${nid}["${label}"]`);
  }
  for (const edge of tree.edges) {
    const from = nodeIds.get(edge.from);
    const to = nodeIds.get(edge.to);
    if (from && to) {
      lines.push(`  ${from} --> ${to}`);
    }
  }
  return lines.join("\n");
};

const MAX_NODES = 50;

export const ExplorerGraph2D = ({
  graph,
  indexFns,
}: Props): React.JSX.Element => {
  const mermaidCode = useMemo(() => {
    const fullTree = buildTree(graph, indexFns);
    const pruned = pruneTree(fullTree, MAX_NODES);
    return treeToMermaid(pruned);
  }, [graph, indexFns]);

  const tree = useMemo(() => buildTree(graph, indexFns), [graph, indexFns]);
  const isPruned = tree.nodes.size > MAX_NODES;

  return (
    <ScrollArea className="h-full">
      <div className="p-4">
        {isPruned && (
          <p className="mb-2 text-xs text-muted-foreground">
            Showing top {MAX_NODES} of {tree.nodes.size} modules by
            connectivity.
          </p>
        )}
        <MermaidDiagram
          code={mermaidCode}
          className="[&_svg]:max-w-full [&_svg]:h-auto"
        />
      </div>
    </ScrollArea>
  );
};
