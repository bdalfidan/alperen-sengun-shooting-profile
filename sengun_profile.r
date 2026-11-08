# =============================================================
# Alperen Sengun: descriptive shooting profile by season
# Regular seasons 2021-22 to 2024-25 | Data: hoopR (ESPN play-by-play)
#
# For each season:
#   - TS% and eFG%
#   - shot distribution by zone
#   - free throw rate (FTA per FGA) and free throw %
#   - shot types
# =============================================================
# install.packages(c("hoopR", "dplyr", "ggplot2", "stringr", "tidyr", "scales"))

library(hoopR)
library(dplyr)
library(ggplot2)
library(stringr)
library(tidyr)
library(scales)

PLAYER  <- "Alperen Sengun"   
SEASONS <- 2022:2026          
HOOP_X  <- 41.75              # hoop centers at x = +/-41.75 ft, y = 0

season_label <- function(yr) sprintf("%d-%02d", yr - 1, yr %% 100)

# -------------------------------------------------------------
# 1. DATA
# -------------------------------------------------------------

get_player_shots <- function(yr) {
  load_nba_pbp(yr) %>%
    filter(season_type == 2,
           shooting_play == TRUE,
           athlete_name_1 == PLAYER) %>%
    transmute(season = season_label(yr), game_id, type_text, text,
              scoring_play, coordinate_x, coordinate_y)
}

all_shots <- bind_rows(lapply(SEASONS, get_player_shots))
if (nrow(all_shots) == 0) stop("No shots found for ", PLAYER)

shots <- all_shots %>%
  mutate(
    is_ft    = str_detect(type_text, "Free Throw"),
    is_made  = as.integer(scoring_play),
    is_three = !is_ft & str_detect(str_to_lower(text), "three point"),
    shot_distance = sqrt((abs(coordinate_x) - HOOP_X)^2 + coordinate_y^2),
    zone = case_when(
      is_ft                ~ NA_character_,
      is_three             ~ "3PT",
      is.na(shot_distance) ~ NA_character_,
      shot_distance <= 4   ~ "Rim (0-4 ft)",
      shot_distance <= 10  ~ "Short (4-10 ft)",
      TRUE                 ~ "Mid-range (2PT, 10+ ft)"
    ),
    points = case_when(
      is_ft    ~ is_made,
      is_three ~ 3L * is_made,
      TRUE     ~ 2L * is_made
    )
  )

# -------------------------------------------------------------
# 2. SEASON SUMMARY
# eFG% = (FGM + 0.5 * 3PM) / FGA
# TS%  = PTS / (2 * (FGA + 0.44 * FTA))
# FT rate = FTA / FGA
# -------------------------------------------------------------

summary_tbl <- shots %>%
  group_by(season) %>%
  summarise(
    games = n_distinct(game_id),
    fga = sum(!is_ft),
    fgm = sum(is_made[!is_ft]),
    tpm = sum(is_made[is_three]),
    fta = sum(is_ft),
    ftm = sum(is_made[is_ft]),
    pts = sum(points),
    efg     = (fgm + 0.5 * tpm) / fga,
    ts      = pts / (2 * (fga + 0.44 * fta)),
    ft_rate = fta / fga,
    ft_pct  = ftm / fta,
    .groups = "drop"
  )
print(summary_tbl, width = Inf)

# -------------------------------------------------------------
# 3. SHOT DISTRIBUTION BY ZONE
# -------------------------------------------------------------

zone_levels <- c("Rim (0-4 ft)", "Short (4-10 ft)", "Mid-range (2PT, 10+ ft)", "3PT")

distribution <- shots %>%
  filter(!is.na(zone)) %>%
  count(season, zone) %>%
  group_by(season) %>%
  mutate(share = n / sum(n)) %>%
  ungroup() %>%
  mutate(zone = factor(zone, levels = zone_levels))
print(distribution, n = Inf)


# -------------------------------------------------------------
# 4. SHOT TYPES
# Groups are built from ESPN's shot labels (type_text). Order matters:
# the first matching rule wins.
# -------------------------------------------------------------

type_levels <- c("Dunk", "Layup", "Hook", "Tip-in", "Floater",
                 "2PT jump shot", "3PT jump shot")

shot_types <- shots %>%
  filter(!is_ft) %>%
  mutate(
    shot_type = case_when(
      is_three                          ~ "3PT jump shot",
      str_detect(type_text, "Dunk")     ~ "Dunk",
      str_detect(type_text, "Layup|Finger Roll") ~ "Layup",
      str_detect(type_text, "Hook")     ~ "Hook",
      str_detect(type_text, "Tip Shot") ~ "Tip-in",
      str_detect(type_text, "Floating") ~ "Floater",
      TRUE                              ~ "2PT jump shot"
    )
  )

type_tbl <- shot_types %>%
  group_by(season, shot_type) %>%
  summarise(attempts = n(), fgm = sum(is_made), .groups = "drop") %>%
  group_by(season) %>%
  mutate(share = attempts / sum(attempts), fg_pct = fgm / attempts) %>%
  ungroup() %>%
  mutate(shot_type = factor(shot_type, levels = rev(type_levels)),
         # dark text on light cells, white text on dark cells
         txt = if_else(share > 0.5 * max(share), "white", "grey15"))
print(type_tbl, n = Inf)


#  STYLE: one shared theme and palette for all plots

COL_RED  <- "#CE1141"
COL_GRAY <- "#4D4D4D"
CAPTION  <- "Source: ESPN play-by-play via hoopR | Regular seasons only"

ZONE_COLS <- c("Rim (0-4 ft)"             = "#CE1141",
               "Short (4-10 ft)"          = "#F28E2B",
               "Mid-range (2PT, 10+ ft)"  = "#9AA0A6",
               "3PT"                      = "#1F3A5F")
ZONE_TEXT <- c("Rim (0-4 ft)"             = "white",
               "Short (4-10 ft)"          = "grey10",
               "Mid-range (2PT, 10+ ft)"  = "grey10",
               "3PT"                      = "white")

theme_sengun <- function(base_size = 14) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.background    = element_rect(fill = "white", color = NA),
      panel.grid.minor   = element_blank(),
      panel.grid.major.x = element_blank(),
      panel.grid.major.y = element_line(color = "grey90", linewidth = 0.4),
      plot.title    = element_text(face = "bold", size = base_size + 5,
                                   margin = margin(b = 4)),
      plot.subtitle = element_text(color = "grey35", size = base_size - 1,
                                   margin = margin(b = 14)),
      plot.caption  = element_text(color = "grey55", size = base_size - 4,
                                   hjust = 0, margin = margin(t = 14)),
      plot.title.position   = "plot",
      plot.caption.position = "plot",
      axis.text  = element_text(color = "grey30"),
      axis.title = element_text(color = "grey30"),
      legend.position      = "top",
      legend.justification = "left",
      legend.text          = element_text(size = base_size - 2),
      plot.margin = margin(18, 24, 12, 18)
    )
}

# -------------------------------------------------------------
#  PLOTS
# -------------------------------------------------------------

# 6.1 Scoring efficiency: two lines, direct labels instead of a legend
n_seasons <- nrow(summary_tbl)
peak      <- summary_tbl[which.max(summary_tbl$ts), ]
latest    <- summary_tbl[n_seasons, ]
peak_idx  <- which.max(summary_tbl$ts)

p_eff <- ggplot(summary_tbl, aes(x = season, group = 1)) +
  annotate("rect", xmin = peak_idx - 0.45, xmax = peak_idx + 0.45,
           ymin = -Inf, ymax = Inf, fill = COL_RED, alpha = 0.07) +
  geom_line(aes(y = ts),  color = COL_RED,  linewidth = 1.6) +
  geom_line(aes(y = efg), color = COL_GRAY, linewidth = 1.6) +
  geom_point(aes(y = ts),  color = COL_RED,  size = 5) +
  geom_point(aes(y = efg), color = COL_GRAY, size = 5) +
  geom_point(aes(y = ts),  color = "white", size = 1.8) +
  geom_point(aes(y = efg), color = "white", size = 1.8) +
  geom_text(aes(y = ts,  label = percent(ts,  accuracy = 0.1)),
            vjust = -1.3, color = COL_RED,  fontface = "bold", size = 4.4) +
  geom_text(aes(y = efg, label = percent(efg, accuracy = 0.1)),
            vjust = 2.1,  color = COL_GRAY, fontface = "bold", size = 4.4) +
  annotate("text", x = n_seasons + 0.2, y = latest$ts,  label = "TS%",
           hjust = 0, color = COL_RED,  fontface = "bold", size = 5.2) +
  annotate("text", x = n_seasons + 0.2, y = latest$efg, label = "eFG%",
           hjust = 0, color = COL_GRAY, fontface = "bold", size = 5.2) +
  scale_x_discrete(expand = expansion(add = c(0.5, 1.1))) +
  scale_y_continuous(labels = percent_format(accuracy = 1),
                     limits = c(0.45, 0.65), breaks = seq(0.45, 0.65, 0.05)) +
  theme_sengun() +
  theme(legend.position = "none") +
  labs(title = paste0(PLAYER, ": Scoring Efficiency"),
       subtitle = sprintf("True shooting peaked at %s in %s and was %s in %s",
                          percent(peak$ts, accuracy = 0.1), peak$season,
                          percent(latest$ts, accuracy = 0.1), latest$season),
       caption = paste0(CAPTION, "\nTS% includes free throws, eFG% counts only field goals."),
       x = NULL, y = NULL)
print(p_eff)

# 6.2 Shot distribution: stacked bars, rim at the bottom
rim <- distribution %>% filter(zone == "Rim (0-4 ft)")
mid <- distribution %>% filter(zone == "Mid-range (2PT, 10+ ft)")

p_dist <- ggplot(distribution, aes(x = season, y = share, fill = zone)) +
  geom_col(width = 0.72, position = position_stack(reverse = TRUE)) +
  geom_text(data = filter(distribution, share >= 0.04),
            aes(label = percent(share, accuracy = 1), color = zone),
            position = position_stack(vjust = 0.5, reverse = TRUE),
            fontface = "bold", size = 4.4) +
  scale_fill_manual(values = ZONE_COLS, name = NULL) +
  scale_color_manual(values = ZONE_TEXT, guide = "none") +
  scale_y_continuous(labels = percent_format(accuracy = 1),
                     expand = expansion(mult = c(0, 0.02))) +
  theme_sengun() +
  labs(title = paste0(PLAYER, ": Where the Shots Come From"),
       subtitle = sprintf("Shots at the rim went from %s to %s of his attempts; mid-range twos from %s to %s",
                          percent(rim$share[1], accuracy = 1),
                          percent(rim$share[nrow(rim)], accuracy = 1),
                          percent(mid$share[1], accuracy = 1),
                          percent(mid$share[nrow(mid)], accuracy = 1)),
       caption = CAPTION,
       x = NULL, y = "Share of field goal attempts")
print(p_dist)

# 6.3 Free throws: two small line panels with direct labels
ft_long <- summary_tbl %>%
  select(season, ft_rate, ft_pct) %>%
  pivot_longer(c(ft_rate, ft_pct), names_to = "metric", values_to = "value") %>%
  mutate(metric = recode(metric,
                         ft_rate = "Free throw rate (FTA per FGA)",
                         ft_pct  = "Free throw %"),
         label = if_else(metric == "Free throw %",
                         percent(value, accuracy = 0.1),
                         number(value, accuracy = 0.01)))

p_ft <- ggplot(ft_long, aes(x = season, y = value, group = 1)) +
  geom_line(color = COL_RED, linewidth = 1.6) +
  geom_point(color = COL_RED, size = 5) +
  geom_point(color = "white", size = 1.8) +
  geom_text(aes(label = label), vjust = -1.3, color = COL_RED,
            fontface = "bold", size = 4.4) +
  facet_wrap(~ metric, scales = "free_y") +
  scale_y_continuous(expand = expansion(mult = c(0.2, 0.25))) +
  theme_sengun() +
  theme(axis.text.y = element_blank(),
        strip.text = element_text(face = "bold", size = 13, hjust = 0),
        panel.spacing = unit(2, "lines")) +
  labs(title = paste0(PLAYER, ": Free Throws"),
       subtitle = "How often he gets to the line and how well he shoots there (each panel has its own scale)",
       caption = CAPTION,
       x = NULL, y = NULL)
print(p_ft)

# 6.4 Shot types: heatmap with share (bold) and FG% (below)
p_type <- ggplot(type_tbl, aes(x = season, y = shot_type, fill = share)) +
  geom_tile(color = "white", linewidth = 1.4) +
  geom_text(aes(label = percent(share, accuracy = 1), color = txt),
            nudge_y = 0.16, fontface = "bold", size = 5) +
  geom_text(aes(label = paste0("FG ", percent(fg_pct, accuracy = 1)), color = txt),
            nudge_y = -0.2, size = 3.8) +
  scale_fill_gradient(low = "#FBEAEC", high = COL_RED, guide = "none") +
  scale_color_identity() +
  scale_x_discrete(position = "top") +
  theme_sengun() +
  theme(panel.grid = element_blank(),
        axis.text.y = element_text(size = 13),
        axis.text.x = element_text(size = 13, face = "bold")) +
  labs(title = paste0(PLAYER, ": Shot Types"),
       subtitle = "Bold: share of attempts. Below: FG%. Small groups (tip-ins, floaters) are noisy.",
       caption = CAPTION,
       x = NULL, y = NULL)
print(p_type) 

# SAVE

write.csv(summary_tbl, "sengun_season_summary.csv", row.names = FALSE)
ggsave("sengun_efficiency.png",   p_eff,  width = 9,  height = 5.5, dpi = 200, bg = "white")
ggsave("sengun_distribution.png", p_dist, width = 9,  height = 6,   dpi = 200, bg = "white")
ggsave("sengun_free_throws.png",  p_ft,   width = 11, height = 5,   dpi = 200, bg = "white")
ggsave("sengun_shot_types.png",   p_type, width = 11, height = 6.5, dpi = 200, bg = "white")