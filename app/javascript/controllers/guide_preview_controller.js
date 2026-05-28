import { Controller } from "@hotwired/stimulus";

// Live preview for mission guide_body / submission_guide textareas. Posts the
// markdown to a manage-side endpoint that runs the same renderer the public
// page uses, so authors see shortcodes and sanitization exactly as users
// will. Debounced to avoid hammering the server on every keystroke.
//
// The endpoint caps input at 100 KB and returns 413; we treat that as a
// no-op so the previous preview stays in place.
export default class extends Controller {
  static targets = ["input", "preview"];
  static values = { url: String };

  connect() {
    this.update();
  }

  update() {
    const markdown = this.inputTarget.value || "";
    if (markdown.trim() === "") {
      this.previewTarget.innerHTML =
        '<span class="guide-preview__empty">Preview will appear here…</span>';
      return;
    }

    clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => {
      this.fetchPreview(markdown);
    }, 350);
  }

  async fetchPreview(markdown) {
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
            ?.content,
        },
        body: new URLSearchParams({ markdown }),
      });

      if (response.ok) {
        const html = await response.text();
        this.previewTarget.innerHTML =
          html ||
          '<span class="guide-preview__empty">Preview will appear here…</span>';
      }
    } catch (_e) {
      // Network errors leave the previous preview in place.
    }
  }
}
