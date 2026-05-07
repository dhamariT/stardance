# Centralized onboarding dialogue copy. Single source of truth for any string
# Astronaut Orpheus says during onboarding flows — first-visit home intro, per-tab
# briefings, and inline feedback after a user takes a key action.
#
# Update copy here and only here.
module OnboardingCopy
  HOME_INTRO_STEPS = [
    { selector: nil,                                  text: "Welcome to Stardance, explorer! Let me show you around." },
    { selector: "[data-onboarding-target='home']", text: "This is Home — your home base. You'll come back here to track your progress and see what's next." },
    { selector: "[data-onboarding-target='projects']", text: "Projects is your space. You'll start the things you build here, and post devlogs as you go." },
    { selector: "[data-onboarding-target='shop']",    text: "And the Shop is where you trade the Stardust you earn for cool prizes." },
    { selector: nil,                                  text: "That's the gist! Drop into each tab whenever you're ready — I'll be around if you need me." }
  ].freeze

  TAB_INTROS = {
    visit_projects: [
      "This is Projects — your space for the things you build and ship.",
      "Hit 'New project' when you're ready to start building. Post devlogs as you go to keep a record of your progress."
    ].freeze,

    visit_shop: [
      "Welcome to the Shop! This is where you trade the Stardust you earn for cool prizes.",
      "Some items unlock as you make progress — like free stickers, which open up after you post your first devlog."
    ].freeze
  }.freeze

  PROJECT_CREATED_WITH_HOURS = ->(human_duration) {
    [
      "Hmmm... your project has #{human_duration} tracked already — nice work!",
      "You're ready to post your first devlog.",
      "Never go over 10 hours without logging progress as it might get lost!"
    ]
  }

  PROJECT_CREATED_NO_HOURS = [
    "Good job — you created a project! Now write some code for a bit and track hours in your code editor.",
    "Once you have some time tracked, come back here and post a devlog.",
    "Remember, post devlogs every few hours. Not posting a devlog after over 10 hours of tracked time might lead to it being lost!"
  ].freeze

  FIRST_DEVLOG_POSTED = [
    "Yay! You just earned free stickers for posting your first devlog — claim them from Home!",
    "Now ship your project (when you're happy with it) to earn Stardust and exchange those for stuff in the shop.",
    "Good luck! Remember, anyone can build — go make something amazing!"
  ].freeze
end
