import { Controller } from "@hotwired/stimulus";

// Saves the current scroll position to sessionStorage whenever a form inside
// this controller's scope is submitted, then restores it on the next page
// load. Keeps the manage edit page from jumping to top every time you
// reorder a step / remove a prize / etc. Only form submits trigger a save —
// plain link clicks (e.g. language tabs) still reset to top as expected.
export default class extends Controller {
  connect() {
    this.restoreOnce();
    this.handler = this.save.bind(this);
    this.element.addEventListener("submit", this.handler, true);
  }

  disconnect() {
    if (this.handler) {
      this.element.removeEventListener("submit", this.handler, true);
    }
  }

  storageKey() {
    return `stardance:scroll:${window.location.pathname}${window.location.search}`;
  }

  save() {
    try {
      sessionStorage.setItem(this.storageKey(), String(window.scrollY));
    } catch {
      // sessionStorage can throw on quota / private mode — non-fatal.
    }
  }

  restoreOnce() {
    try {
      const raw = sessionStorage.getItem(this.storageKey());
      if (!raw) return;
      sessionStorage.removeItem(this.storageKey());
      const y = parseInt(raw, 10);
      if (Number.isNaN(y)) return;
      // Wait a frame so layout settles (images/fonts) before scrolling.
      requestAnimationFrame(() => window.scrollTo(0, y));
    } catch {
      // fail silent
    }
  }
}
