/**
 * @file Tests for search view message types and converters.
 */

import { digestMatchToItem, searchHitToItem, grepMatchToItem } from "./messages.ts";
import { similarityPairToItem } from "../explore/messages.ts";

describe("digestMatchToItem", () => {
  it("converts a DigestMatch to SearchResultItem", () => {
    const match = {
      name: "parseConfig",
      file: "/src/config/parser.ts",
      score: 0.85,
      summary: "Parses the configuration file into a typed object",
    };
    const result = digestMatchToItem(match);
    expect(result.label).toBe("parseConfig");
    expect(result.description).toBe("/src/config/parser.ts");
    expect(result.detail).toBe("Parses the configuration file into a typed object");
    expect(result.filePath).toBe("/src/config/parser.ts");
    expect(result.score).toBe(0.85);
    expect(result.icon).toBe("symbol-method");
  });

  it("preserves all fields from the match", () => {
    const match = {
      name: "formatOutput",
      file: "/src/utils/format.ts",
      score: 0.42,
      summary: "Formats output for display",
    };
    const result = digestMatchToItem(match);
    expect(result).toEqual({
      label: "formatOutput",
      description: "/src/utils/format.ts",
      detail: "Formats output for display",
      filePath: "/src/utils/format.ts",
      score: 0.42,
      icon: "symbol-method",
    });
  });
});

describe("searchHitToItem", () => {
  it("converts a SearchHit to SearchResultItem", () => {
    const hit = {
      id: "1",
      title: "parseConfig",
      source: "/src/config/parser.ts",
      line: 10,
      kind: "function",
      score: 0.9,
    };
    const result = searchHitToItem(hit);
    expect(result.label).toBe("parseConfig");
    expect(result.description).toBe("/src/config/parser.ts:10");
    expect(result.filePath).toBe("/src/config/parser.ts");
    expect(result.line).toBe(10);
    expect(result.score).toBe(0.9);
    expect(result.icon).toBe("symbol-file");
  });

  it("omits line from description when line is 0", () => {
    const hit = {
      id: "2",
      title: "readme",
      source: "/README.md",
      line: 0,
      kind: "document",
      score: 0.5,
    };
    const result = searchHitToItem(hit);
    expect(result.description).toBe("/README.md");
  });
});

describe("grepMatchToItem", () => {
  it("converts a GrepMatch to SearchResultItem", () => {
    const match = {
      file: "/src/lib.ts",
      line: 42,
      matched: "pub fn parse",
      name: "parse",
      kind: "function",
      detail: "public function",
    };
    const result = grepMatchToItem(match);
    expect(result.label).toBe("parse");
    expect(result.description).toBe("/src/lib.ts:42");
    expect(result.detail).toBe("public function");
    expect(result.icon).toBe("symbol-keyword");
  });

  it("falls back to matched text when name is missing", () => {
    const match = {
      file: "/src/lib.ts",
      line: 10,
      matched: "import foo",
    };
    const result = grepMatchToItem(match);
    expect(result.label).toBe("import foo");
  });
});

describe("similarityPairToItem", () => {
  it("extracts basenames for the label", () => {
    const pair = {
      file1: "/src/a/foo.ts",
      file2: "/src/b/bar.ts",
      similarity: 0.87,
    };
    const result = similarityPairToItem(pair);
    expect(result.label).toBe("foo.ts ↔ bar.ts");
    expect(result.file1).toBe("/src/a/foo.ts");
    expect(result.file2).toBe("/src/b/bar.ts");
    expect(result.similarity).toBe(0.87);
  });
});
