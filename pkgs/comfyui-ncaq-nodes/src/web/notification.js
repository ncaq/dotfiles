import { app } from "../../scripts/app.js";
import { api } from "../../scripts/api.js";

app.registerExtension({
  name: "save-svt-av1.notification",
  setup() {
    api.addEventListener("save-svt-av1.warning", ({ detail }) => {
      app.extensionManager.toast.add({
        severity: "warn",
        summary: detail.summary,
        detail: detail.detail,
        life: detail.life,
      });
    });
  },
});
