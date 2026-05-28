import { Controller } from "@hotwired/stimulus";

// Segmented control above the guide sidebar that lets a builder switch
// between programming-language variants of the guide. Each option carries a
// data-language attribute; clicking it reloads the page with ?language=X.
// We do a full reload because the page server-renders different sections per
// language, including the section completion state.
//
// Per-mission, the picked language is also written to localStorage so that
// a user who hops away and back lands in their preferred variant. The
// auto-honor of that preference is deliberately gated: we only act on it
// when the URL has no language query, AND we only redirect once per page
// load, AND only if the stored language is currently available. Deep links
// like /missions/x/guide?language=Python always win.
export default class extends Controller {
  static targets = ["option"];
  static values = {
    missionSlug: String,
    currentLanguage: String,
    availableLanguages: Array,
  };

  connect() {
    this.optionTargets.forEach((opt) => {
      const lang = opt.dataset.language;
      opt.classList.toggle(
        "mission-guide__lang-toggle-option--active",
        lang === this.currentLanguageValue,
      );
      opt.setAttribute(
        "aria-pressed",
        lang === this.currentLanguageValue ? "true" : "false",
      );
    });

    this.maybeHonorPreference();
  }

  storageKey() {
    return `stardance:v1:mission-guide-lang:${this.missionSlugValue}`;
  }

  maybeHonorPreference() {
    try {
      const url = new URL(window.location.href);
      if (url.searchParams.has("language")) return;

      const stored = window.localStorage.getItem(this.storageKey());
      if (!stored || stored === this.currentLanguageValue) return;
      if (!this.availableLanguagesValue.includes(stored)) return;

      url.searchParams.set("language", stored);
      window.location.replace(url.toString());
    } catch {
      // localStorage might be unavailable; that's fine
    }
  }

  select(event) {
    event.preventDefault();
    const lang = event.currentTarget.dataset.language;
    if (!lang || lang === this.currentLanguageValue) return;

    try {
      window.localStorage.setItem(this.storageKey(), lang);
    } catch {
      // fail silent
    }

    const url = new URL(window.location.href);
    url.searchParams.set("language", lang);
    url.hash = "";
    window.location.assign(url.toString());
  }
}
