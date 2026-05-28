import { Controller } from "@hotwired/stimulus";

// Drives the mission guide subpage as a tabbed flow. Each step section becomes
// its own tab; the sidebar outline doubles as tab control. Completion is
// driven by an explicit "Mark this section done" button on each section.
//
// Sections are keyed on mission_step_id (a stable integer shared across every
// language of the guide). When the user has an active project attached to
// this mission, completions are persisted server-side. When the user is
// signed out or has no project on this mission, the controller falls back
// to versioned localStorage keyed on the mission slug alone (no language
// partition — step ids are themselves shared).
//
// Tab activation sources, in order:
//   - URL hash matching a section id (e.g. #step-42)
//   - User clicks an outline link
//   - User clicks the prev/next nav at the bottom of a section
//   - Default: the first section
export default class extends Controller {
  static targets = ["outlineItem", "progressBar", "completedCount"];
  static values = {
    sectionCount: Number,
    missionSlug: String,
    missionId: String,
    projectId: String,
    createUrl: String,
    completedStepIds: Array,
  };

  connect() {
    this.sections = Array.from(
      document.querySelectorAll("section.guide-section[data-mission-step-id]"),
    );

    // Completion set holds mission_step_id values as numbers.
    this.completed = new Set(
      (this.completedStepIdsValue || []).map((id) => Number(id)),
    );
    if (!this.hasProjectIdValue || !this.projectIdValue) {
      this.hydrateFromLocalStorage();
    }

    if (this.sections.length === 0) {
      this.renderProgress();
      return;
    }

    this.injectPrevNext();
    this.bindOutlineClicks();
    this.bindHashChange();

    const initial = this.indexFromHash() ?? this.firstIncompleteIndex() ?? 0;
    this.activate(initial, { scroll: false, updateHash: false });
    this.renderProgress();
  }

  firstIncompleteIndex() {
    for (const section of this.sections) {
      const stepId = this.stepIdFor(section);
      if (stepId !== null && !this.completed.has(stepId)) {
        const idx = Number(section.dataset.sectionIndex);
        return Number.isNaN(idx) ? null : idx;
      }
    }
    return null;
  }

  disconnect() {
    if (this.onHashChange) {
      window.removeEventListener("hashchange", this.onHashChange);
    }
  }

  // ---- Storage helpers ----------------------------------------------------

  // Step ids are shared across languages, so the storage key doesn't need a
  // language partition — completion in JS == completion in Python.
  storageKey() {
    const slug = this.hasMissionSlugValue ? this.missionSlugValue : "_";
    return `stardance:v1:mission-progress:${slug}`;
  }

  hydrateFromLocalStorage() {
    try {
      const raw = window.localStorage.getItem(this.storageKey());
      if (!raw) return;
      const data = JSON.parse(raw);
      if (Array.isArray(data.stepIds)) {
        data.stepIds.forEach((id) => this.completed.add(Number(id)));
      }
    } catch {
      // fail silent — quota or parse problem, just skip hydration
    }
  }

  persistToLocalStorage() {
    try {
      window.localStorage.setItem(
        this.storageKey(),
        JSON.stringify({ stepIds: Array.from(this.completed) }),
      );
    } catch {
      // fail silent
    }
  }

  // ---- Activation (tab swap) ----------------------------------------------

  bindOutlineClicks() {
    this.outlineItemTargets.forEach((item) => {
      const link = item.querySelector(".mission-guide__outline-link");
      if (!link) return;
      link.addEventListener("click", (e) => {
        e.preventDefault();
        const idx = Number(item.dataset.sectionIndex);
        if (!Number.isNaN(idx)) this.activate(idx);
      });
    });
  }

  bindHashChange() {
    this.onHashChange = () => {
      const idx = this.indexFromHash();
      if (idx !== null) this.activate(idx, { updateHash: false });
    };
    window.addEventListener("hashchange", this.onHashChange);
  }

  indexFromHash() {
    const hash = window.location.hash.replace(/^#/, "");
    if (!hash) return null;
    const section = this.sections.find((s) => s.id === hash);
    if (!section) return null;
    const idx = Number(section.dataset.sectionIndex);
    return Number.isNaN(idx) ? null : idx;
  }

  activate(index, { scroll = true, updateHash = true } = {}) {
    this.activeIndex = index;

    this.sections.forEach((section) => {
      const idx = Number(section.dataset.sectionIndex);
      section.classList.toggle("guide-section--hidden", idx !== index);
    });

    this.outlineItemTargets.forEach((item) => {
      const idx = Number(item.dataset.sectionIndex);
      item.classList.toggle("is-current", idx === index);
      const link = item.querySelector(".mission-guide__outline-link");
      if (link) {
        if (idx === index) {
          link.setAttribute("aria-current", "location");
        } else {
          link.removeAttribute("aria-current");
        }
      }
    });

    if (updateHash) {
      const activeSection = this.sections.find(
        (s) => Number(s.dataset.sectionIndex) === index,
      );
      if (activeSection) {
        history.replaceState(null, "", `#${activeSection.id}`);
      }
    }

    if (scroll) {
      this.element.scrollIntoView({ behavior: "smooth", block: "start" });
    }

    this.renderProgress();
  }

  // ---- Progress rendering -------------------------------------------------

  stepIdFor(section) {
    if (!section) return null;
    const raw = section.dataset.missionStepId;
    if (!raw) return null;
    const n = Number(raw);
    return Number.isNaN(n) ? null : n;
  }

  outlineStepIdFor(item) {
    if (!item) return null;
    const raw = item.dataset.missionStepId;
    if (!raw) return null;
    const n = Number(raw);
    return Number.isNaN(n) ? null : n;
  }

  renderProgress() {
    const total = this.hasSectionCountValue
      ? this.sectionCountValue
      : this.outlineItemTargets.length;

    let completedCount = 0;
    this.outlineItemTargets.forEach((item) => {
      const stepId = this.outlineStepIdFor(item);
      const isComplete = stepId !== null && this.completed.has(stepId);
      item.classList.toggle("is-completed", !!isComplete);
      const marker = item.querySelector(".mission-guide__outline-marker");
      if (marker) marker.textContent = isComplete ? "✓" : "○";
      if (isComplete) completedCount += 1;
    });

    if (this.hasProgressBarTarget) {
      this.progressBarTarget.value = completedCount;
      this.progressBarTarget.max = total;
    }
    if (this.hasCompletedCountTarget) {
      this.completedCountTarget.textContent = String(completedCount);
    }
  }

  // ---- Mark-complete persistence -----------------------------------------

  // Apply (or clear) a completion state for a section. Optimistic UI update
  // with a rollback if the server rejects. Used both by the explicit
  // "Mark this section done" button and by the prev/next nav (which marks
  // the section being left complete when moving forward, incomplete when
  // moving backward).
  setSectionState(stepId, desired) {
    const wasComplete = this.completed.has(stepId);
    if (wasComplete === desired) return;

    if (desired) this.completed.add(stepId);
    else this.completed.delete(stepId);
    this.renderProgress();

    if (
      this.hasProjectIdValue &&
      this.projectIdValue &&
      this.hasCreateUrlValue &&
      this.createUrlValue
    ) {
      this.persistRemote({ stepId, desired }).catch(() => {
        if (wasComplete) this.completed.add(stepId);
        else this.completed.delete(stepId);
        this.renderProgress();
      });
    } else {
      this.persistToLocalStorage();
    }
  }

  async persistRemote({ stepId, desired }) {
    const tokenEl = document.querySelector('meta[name="csrf-token"]');
    const token = tokenEl?.getAttribute("content") || "";
    const body = {
      mission_step_id: stepId,
      completed: desired,
    };
    const response = await fetch(this.createUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": token,
      },
      body: JSON.stringify(body),
    });
    if (!response.ok) {
      throw new Error(`Server responded ${response.status}`);
    }
  }

  // ---- DOM injection ------------------------------------------------------

  injectPrevNext() {
    this.sections.forEach((section) => {
      const idx = Number(section.dataset.sectionIndex);
      if (Number.isNaN(idx)) return;

      // Strip trailing <hr>s so the section doesn't render a horizontal
      // rule butting up against the prev/next nav's own border-top.
      // The body is wrapped in `<div class="guide-content">`, so the
      // trailing HR sits one level inside the section — walk into the
      // wrapper to find it.
      const stripTrailingHrs = (root) => {
        let candidate = root.lastElementChild;
        while (candidate && candidate.tagName === "HR") {
          const prev = candidate.previousElementSibling;
          candidate.remove();
          candidate = prev;
        }
      };
      stripTrailingHrs(section);
      const wrapper = section.querySelector(":scope > .guide-content");
      if (wrapper) stripTrailingHrs(wrapper);

      const nav = document.createElement("nav");
      nav.className = "mission-guide__step-nav";
      nav.setAttribute("aria-label", "Section navigation");

      const prev = this.makeNavButton(idx - 1, "prev");
      const next = this.makeNavButton(idx + 1, "next");

      if (prev) {
        nav.appendChild(prev);
      } else {
        const spacer = document.createElement("span");
        spacer.className = "mission-guide__step-nav-spacer";
        nav.appendChild(spacer);
      }
      if (next) nav.appendChild(next);

      section.appendChild(nav);
    });
  }

  makeNavButton(targetIndex, direction) {
    const target = this.sections.find(
      (s) => Number(s.dataset.sectionIndex) === targetIndex,
    );
    if (!target) return null;
    const heading = target.querySelector("h2");
    const label = heading
      ? heading.textContent.trim()
      : `Section ${targetIndex + 1}`;

    const button = document.createElement("button");
    button.type = "button";
    button.className = `mission-guide__step-nav-button mission-guide__step-nav-button--${direction}`;
    button.dataset.targetIndex = String(targetIndex);

    const eyebrow = document.createElement("span");
    eyebrow.className = "mission-guide__step-nav-eyebrow";
    eyebrow.textContent = direction === "prev" ? "← Previous" : "Next →";

    const title = document.createElement("span");
    title.className = "mission-guide__step-nav-title";
    title.textContent = label;

    button.appendChild(eyebrow);
    button.appendChild(title);
    button.addEventListener("click", () => {
      if (direction === "next") {
        // Forward: mark the section being LEFT as done.
        const current = this.sections.find(
          (s) => Number(s.dataset.sectionIndex) === this.activeIndex,
        );
        const currentStepId = current ? this.stepIdFor(current) : null;
        if (currentStepId !== null) this.setSectionState(currentStepId, true);
      } else {
        // Backward: mark the section being navigated TO as not done.
        const destStepId = this.stepIdFor(target);
        if (destStepId !== null) this.setSectionState(destStepId, false);
      }
      this.activate(targetIndex);
    });

    return button;
  }
}
