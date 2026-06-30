import {
  defineConfig
} from "../../chunk-CUZC63FW.mjs";
import "../../chunk-LRTAKWDY.mjs";
import {
  init_esm
} from "../../chunk-5QNIFE2Q.mjs";

// trigger.config.ts
init_esm();
var trigger_config_default = defineConfig({
  project: "proj_ejbymoiwjvnqcuvlbohm",
  dirs: ["./src/trigger"],
  // 5 minutes — enough for PDF download + Vertex AI analysis + embedding + DB writes
  maxDuration: 300,
  build: {}
});
var resolveEnvVars = void 0;
export {
  trigger_config_default as default,
  resolveEnvVars
};
//# sourceMappingURL=trigger.config.mjs.map
