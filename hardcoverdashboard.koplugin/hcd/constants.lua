return {
    API_URL = "https://api.hardcover.app/v1/graphql",
    USER_AGENT = "hardcoverdashboard.koplugin/0.2.0",
    STATUS_READING = 2,
    JOURNAL_EVENTS = {
        "progress_updated",
        "user_book_read_started",
        "user_book_read_finished",
        "status_currently_reading",
        "status_read",
    },
    DEFAULTS = {
        week_start = 1, -- 1 = Sunday (matches Hardcover), 2 = Monday
        show_covers = true,
    },
    CACHE_TTL = 1800,
    MAX_JOURNAL_PAGES = 20,
    MAX_STREAK_PAGES = 10,
    -- Hardcover-inspired vibrant palette for color e-ink (Kaleido 3)
    COLORS = {
        "#5B67F1", -- indigo
        "#F97316", -- orange
        "#06B6D4", -- cyan
        "#EC4899", -- magenta / pink
        "#F43F5E", -- rose / red
        "#EAB308", -- amber / gold
        "#10B981", -- emerald
        "#8B5CF6", -- violet
    },
    -- Distinct grayscale shades for monochrome e-ink screens
    GRAYS = {
        "#1F2937",
        "#4B5563",
        "#6B7280",
        "#374151",
        "#111827",
        "#52525B",
        "#71717A",
        "#27272A",
    },
    -- UI Theme tokens (color e-ink)
    THEME_COLOR = {
        canvas_bg = "#F4F6FA",
        card_bg = "#FFFFFF",
        card_border = "#DFE4EE",
        cell_bg = "#FAFBFD",
        cell_border = "#E6EAF2",
        today_border = "#5B67F1",
        today_bg = "#F2F4FF",
        today_text = "#4F46E5",
        text_primary = "#111827",
        text_secondary = "#64748B",
        text_muted = "#94A3B8",
        pill_bg = "#EEF1F6",
        pill_text = "#334155",
        page_badge_bg = "#2D3139",
        page_badge_text = "#FFFFFF",
        progress_track = "#E5E7EB",
        progress_reading = "#5B67F1",
        progress_goal = "#F5B800",
    },
    -- UI Theme tokens (grayscale e-ink)
    THEME_GRAY = {
        canvas_bg = "#FFFFFF",
        card_bg = "#FFFFFF",
        card_border = "#BDBDBD",
        cell_bg = "#FFFFFF",
        cell_border = "#D4D4D4",
        today_border = "#000000",
        today_bg = "#F0F0F0",
        today_text = "#000000",
        text_primary = "#000000",
        text_secondary = "#444444",
        text_muted = "#777777",
        pill_bg = "#EAEAEA",
        pill_text = "#111111",
        page_badge_bg = "#222222",
        page_badge_text = "#FFFFFF",
        progress_track = "#DDDDDD",
        progress_reading = "#333333",
        progress_goal = "#222222",
    },
}
