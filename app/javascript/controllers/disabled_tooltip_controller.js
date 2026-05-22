import { Controller } from "@hotwired/stimulus";

// Hover/focus tooltip that reuses the .locked-tab-popover visual style from
// the sidebar. Use on a wrapper around a disabled control so the hover target
// is the wrapper, not the disabled element itself.
export default class extends Controller {
  static values = {
    message: String,
    position: { type: String, default: "right" },
  };

  connect() {
    this.boundShow = this.show.bind(this);
    this.boundHide = this.hide.bind(this);
    this.boundKey = this.handleKey.bind(this);
    this.boundReposition = this.reposition.bind(this);

    this.element.addEventListener("mouseenter", this.boundShow);
    this.element.addEventListener("mouseleave", this.boundHide);
    this.element.addEventListener("focusin", this.boundShow);
    this.element.addEventListener("focusout", this.boundHide);
  }

  disconnect() {
    this.element.removeEventListener("mouseenter", this.boundShow);
    this.element.removeEventListener("mouseleave", this.boundHide);
    this.element.removeEventListener("focusin", this.boundShow);
    this.element.removeEventListener("focusout", this.boundHide);
    this.hide();
  }

  show() {
    if (this.popover) return;

    this.popover = document.createElement("div");
    this.popover.className = "locked-tab-popover";
    if (this.positionValue === "top") {
      this.popover.classList.add("locked-tab-popover--top");
    }
    this.popover.setAttribute("role", "tooltip");
    this.popover.textContent = this.messageValue;
    document.body.appendChild(this.popover);

    this.reposition();

    requestAnimationFrame(() => {
      if (this.popover)
        this.popover.classList.add("locked-tab-popover--visible");
    });

    document.addEventListener("keydown", this.boundKey);
    window.addEventListener("scroll", this.boundReposition, { passive: true });
    window.addEventListener("resize", this.boundReposition, { passive: true });
  }

  hide() {
    document.removeEventListener("keydown", this.boundKey);
    window.removeEventListener("scroll", this.boundReposition);
    window.removeEventListener("resize", this.boundReposition);

    if (this.popover) {
      this.popover.remove();
      this.popover = null;
    }
  }

  reposition() {
    if (!this.popover) return;
    const rect = this.element.getBoundingClientRect();
    const popoverRect = this.popover.getBoundingClientRect();
    const gap = 12;

    if (this.positionValue === "top") {
      const top = rect.top - popoverRect.height - gap;
      const left = rect.left + rect.width / 2 - popoverRect.width / 2;
      this.popover.style.top = `${Math.max(8, top)}px`;
      this.popover.style.left = `${Math.max(8, left)}px`;
    } else {
      const top = rect.top + rect.height / 2 - popoverRect.height / 2;
      const left = rect.right + gap;
      this.popover.style.top = `${Math.max(8, top)}px`;
      this.popover.style.left = `${left}px`;
    }
  }

  handleKey(event) {
    if (event.key === "Escape") this.hide();
  }
}
