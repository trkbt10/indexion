import { serve } from "@std/http";
import { router } from "./routes.ts";

const PORT = 8000;

console.log(`Server running on http://localhost:${PORT}`);
serve(router, { port: PORT });
