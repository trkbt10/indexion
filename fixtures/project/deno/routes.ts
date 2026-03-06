import { z } from "zod";
import { validate } from "./lib/validator.ts";

const schema = z.object({
  name: z.string(),
});

export function router(req: Request): Response {
  const url = new URL(req.url);

  if (url.pathname === "/") {
    return new Response("Hello, Deno!");
  }

  return new Response("Not Found", { status: 404 });
}
