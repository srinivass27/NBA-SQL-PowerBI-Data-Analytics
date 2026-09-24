-- =====================================================================
-- NBA PLAYER PERFORMANCE ANALYSIS
-- 03_analysis_queries.sql
-- 20 analytical questions: 5 Beginner, 8 Intermediate, 7 Advanced
-- Run after 01_database_schema.sql and 02_data_cleaning.sql
-- =====================================================================

USE nba_analytics;

-- #####################################################################
-- BEGINNER (5)
-- #####################################################################

-- ---------------------------------------------------------------------
-- B1. What are the top 10 highest-scoring single-game performances
--     by any player? (Simple ORDER BY / LIMIT)
-- ---------------------------------------------------------------------
SELECT PLAYER_NAME, TEAM_ABBREVIATION, GAME_ID, PTS
FROM games_details
WHERE PTS IS NOT NULL
ORDER BY PTS DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- B2. How many games were played in each season?
-- ---------------------------------------------------------------------
SELECT SEASON, COUNT(*) AS games_played
FROM games
GROUP BY SEASON
ORDER BY SEASON;

-- ---------------------------------------------------------------------
-- B3. List all 30 teams with their city and arena capacity,
--     largest arena first.
-- ---------------------------------------------------------------------
SELECT ABBREVIATION, NICKNAME, CITY, ARENA, ARENACAPACITY
FROM teams
ORDER BY ARENACAPACITY DESC;

-- ---------------------------------------------------------------------
-- B4. Which teams currently belong to the Eastern vs Western
--     conference, based on the most recent standings date available?
-- ---------------------------------------------------------------------
SELECT TEAM, CONFERENCE
FROM ranking
WHERE STANDINGSDATE = (SELECT MAX(STANDINGSDATE) FROM ranking)
ORDER BY CONFERENCE, TEAM;

-- ---------------------------------------------------------------------
-- B5. What is the average number of points scored per game
--     (home + away combined) across the entire dataset?
-- ---------------------------------------------------------------------
SELECT
    ROUND(AVG(PTS_home), 1) AS avg_home_points,
    ROUND(AVG(PTS_away), 1) AS avg_away_points,
    ROUND(AVG(PTS_home + PTS_away), 1) AS avg_total_points_per_game
FROM games
WHERE PTS_home IS NOT NULL AND PTS_away IS NOT NULL;


-- #####################################################################
-- INTERMEDIATE (8)
-- #####################################################################

-- ---------------------------------------------------------------------
-- I1. Who are the top 10 players by average points per game,
--     among players who appeared in at least 200 games?
--     (GROUP BY + HAVING to filter on an aggregate)
-- ---------------------------------------------------------------------
SELECT
    PLAYER_NAME,
    COUNT(*) AS games_played,
    ROUND(AVG(PTS), 1) AS avg_points
FROM games_details
WHERE PTS IS NOT NULL
GROUP BY PLAYER_NAME
HAVING COUNT(*) >= 200
ORDER BY avg_points DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- I2. For a given season (example: 2018), what was each team's
--     win-loss record and win percentage on the final standings date?
-- ---------------------------------------------------------------------
SELECT r.TEAM, r.CONFERENCE, r.W, r.L, r.W_PCT
FROM ranking r
WHERE r.SEASON_ID = 22018   -- SEASON_ID convention: 2xxxx = regular season
  AND r.STANDINGSDATE = (
        SELECT MAX(r2.STANDINGSDATE)
        FROM ranking r2
        WHERE r2.SEASON_ID = r.SEASON_ID
      )
ORDER BY r.CONFERENCE, r.W_PCT DESC;

-- ---------------------------------------------------------------------
-- I3. Who are the most efficient shooters (highest FG%) among players
--     with a meaningful sample size (at least 500 field-goal attempts
--     across their career in this dataset)?
-- ---------------------------------------------------------------------
SELECT
    PLAYER_NAME,
    SUM(FGA) AS total_attempts,
    SUM(FGM) AS total_makes,
    ROUND(SUM(FGM) / SUM(FGA), 3) AS career_fg_pct
FROM games_details
WHERE FGA IS NOT NULL
GROUP BY PLAYER_NAME
HAVING SUM(FGA) >= 500
ORDER BY career_fg_pct DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- I4. Which teams have the best average 3-point shooting percentage,
--     using team-level game data?
-- ---------------------------------------------------------------------
SELECT
    t.NICKNAME,
    ROUND(AVG(g.FG3_PCT_home), 3) AS avg_home_fg3_pct
FROM games g
JOIN teams t ON g.TEAM_ID_home = t.TEAM_ID
WHERE g.FG3_PCT_home IS NOT NULL
GROUP BY t.NICKNAME
ORDER BY avg_home_fg3_pct DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- I5. How many triple-doubles (PTS >= 10, REB >= 10, AST >= 10 in the
--     same game) has each player recorded? (Conditional aggregation)
-- ---------------------------------------------------------------------
SELECT
    PLAYER_NAME,
    SUM(CASE WHEN PTS >= 10 AND REB >= 10 AND AST >= 10 THEN 1 ELSE 0 END) AS triple_doubles
FROM games_details
WHERE PTS IS NOT NULL
GROUP BY PLAYER_NAME
HAVING triple_doubles > 0
ORDER BY triple_doubles DESC
LIMIT 15;

-- ---------------------------------------------------------------------
-- I6. What is the average rebounds, assists, and points for each
--     starting position (Forward / Center / Guard)?
--     Note: START_POSITION only distinguishes starters (F/C/G);
--     bench players have a NULL position and are excluded here.
-- ---------------------------------------------------------------------
SELECT
    START_POSITION,
    ROUND(AVG(PTS), 1) AS avg_points,
    ROUND(AVG(REB), 1) AS avg_rebounds,
    ROUND(AVG(AST), 1) AS avg_assists
FROM games_details
WHERE START_POSITION IS NOT NULL AND PTS IS NOT NULL
GROUP BY START_POSITION
ORDER BY avg_points DESC;

-- ---------------------------------------------------------------------
-- I7. For each team, how do average home points compare to average
--     away points? (Home-court scoring advantage)
-- ---------------------------------------------------------------------
SELECT
    t.NICKNAME,
    ROUND(AVG(g.PTS_home), 1) AS avg_points_at_home,
    ROUND(AVG(ga.PTS_away), 1) AS avg_points_away,
    ROUND(AVG(g.PTS_home) - AVG(ga.PTS_away), 1) AS home_scoring_advantage
FROM teams t
JOIN games g  ON g.TEAM_ID_home = t.TEAM_ID  AND g.PTS_home IS NOT NULL
JOIN games ga ON ga.TEAM_ID_away = t.TEAM_ID AND ga.PTS_away IS NOT NULL
GROUP BY t.NICKNAME
ORDER BY home_scoring_advantage DESC;

-- ---------------------------------------------------------------------
-- I8. Which players were traded mid-season (played for more than one
--     team in the same season, per the players roster table)?
-- ---------------------------------------------------------------------
SELECT
    PLAYER_NAME,
    SEASON,
    COUNT(DISTINCT TEAM_ID) AS teams_played_for
FROM players
GROUP BY PLAYER_NAME, SEASON
HAVING COUNT(DISTINCT TEAM_ID) > 1
ORDER BY SEASON DESC, teams_played_for DESC;


-- #####################################################################
-- ADVANCED (7)
-- #####################################################################

-- ---------------------------------------------------------------------
-- A1. Who was the leading scorer (by average points per game) in each
--     season? games_details has no SEASON column, so we join to games
--     first. Uses a CTE + RANK() PARTITION BY SEASON.
-- ---------------------------------------------------------------------
WITH player_season_avg AS (
    SELECT
        g.SEASON,
        gd.PLAYER_NAME,
        COUNT(*) AS games_played,
        AVG(gd.PTS) AS avg_pts
    FROM games_details gd
    JOIN games g ON gd.GAME_ID = g.GAME_ID
    WHERE gd.PTS IS NOT NULL
    GROUP BY g.SEASON, gd.PLAYER_NAME
    HAVING COUNT(*) >= 20        -- filter out tiny/late-season sample sizes
),
ranked AS (
    SELECT
        SEASON,
        PLAYER_NAME,
        ROUND(avg_pts, 1) AS avg_pts,
        RANK() OVER (PARTITION BY SEASON ORDER BY avg_pts DESC) AS scoring_rank
    FROM player_season_avg
)
SELECT SEASON, PLAYER_NAME, avg_pts
FROM ranked
WHERE scoring_rank = 1
ORDER BY SEASON;

-- ---------------------------------------------------------------------
-- A2. Running total of wins across a season for a specific team
--     (example: TEAM_ID 1610612747 = Los Angeles Lakers), ordered by
--     date, using a window function running SUM().
-- ---------------------------------------------------------------------
SELECT
    STANDINGSDATE,
    W,
    L,
    W - LAG(W, 1, 0) OVER (ORDER BY STANDINGSDATE) AS win_added_this_snapshot,
    SUM(W - LAG(W, 1, 0) OVER (ORDER BY STANDINGSDATE))
        OVER (ORDER BY STANDINGSDATE) AS running_wins
FROM ranking
WHERE TEAM_ID = 1610612747
  AND SEASON_ID = 22018
ORDER BY STANDINGSDATE;

-- ---------------------------------------------------------------------
-- A3. A simplified Player Efficiency score per game
--     (PTS + REB + AST + STL + BLK - missed FG - missed FT - TOV),
--     then rank all players by their average efficiency (min 100
--     games) using a CTE + window function.
-- ---------------------------------------------------------------------
WITH player_efficiency AS (
    SELECT
        PLAYER_NAME,
        GAME_ID,
        (PTS + REB + AST + STL + BLK
         - (FGA - FGM) - (FTA - FTM) - TOV) AS efficiency_score
    FROM games_details
    WHERE PTS IS NOT NULL
),
player_avg_efficiency AS (
    SELECT
        PLAYER_NAME,
        COUNT(*) AS games_played,
        ROUND(AVG(efficiency_score), 1) AS avg_efficiency
    FROM player_efficiency
    GROUP BY PLAYER_NAME
    HAVING COUNT(*) >= 100
)
SELECT
    PLAYER_NAME,
    games_played,
    avg_efficiency,
    DENSE_RANK() OVER (ORDER BY avg_efficiency DESC) AS efficiency_rank
FROM player_avg_efficiency
ORDER BY efficiency_rank
LIMIT 20;

-- ---------------------------------------------------------------------
-- A4. Who was each team's leading scorer (by total points) in each
--     season? (ROW_NUMBER PARTITION BY TEAM, SEASON)
-- ---------------------------------------------------------------------
WITH team_player_season_totals AS (
    SELECT
        g.SEASON,
        gd.TEAM_ABBREVIATION,
        gd.PLAYER_NAME,
        SUM(gd.PTS) AS total_points
    FROM games_details gd
    JOIN games g ON gd.GAME_ID = g.GAME_ID
    WHERE gd.PTS IS NOT NULL
    GROUP BY g.SEASON, gd.TEAM_ABBREVIATION, gd.PLAYER_NAME
),
ranked_scorers AS (
    SELECT
        SEASON,
        TEAM_ABBREVIATION,
        PLAYER_NAME,
        total_points,
        ROW_NUMBER() OVER (
            PARTITION BY SEASON, TEAM_ABBREVIATION
            ORDER BY total_points DESC
        ) AS scorer_rank
    FROM team_player_season_totals
)
SELECT SEASON, TEAM_ABBREVIATION, PLAYER_NAME, total_points
FROM ranked_scorers
WHERE scorer_rank = 1
ORDER BY SEASON DESC, TEAM_ABBREVIATION;

-- ---------------------------------------------------------------------
-- A5. For every team, compare home win percentage vs away win
--     percentage using conditional aggregation inside a CTE.
-- ---------------------------------------------------------------------
WITH home_results AS (
    SELECT
        TEAM_ID_home AS TEAM_ID,
        AVG(HOME_TEAM_WINS) AS home_win_pct,
        COUNT(*) AS home_games
    FROM games
    GROUP BY TEAM_ID_home
),
away_results AS (
    SELECT
        TEAM_ID_away AS TEAM_ID,
        AVG(1 - HOME_TEAM_WINS) AS away_win_pct,
        COUNT(*) AS away_games
    FROM games
    GROUP BY TEAM_ID_away
)
SELECT
    t.NICKNAME,
    h.home_games,
    ROUND(h.home_win_pct, 3) AS home_win_pct,
    a.away_games,
    ROUND(a.away_win_pct, 3) AS away_win_pct,
    ROUND(h.home_win_pct - a.away_win_pct, 3) AS home_court_edge
FROM teams t
JOIN home_results h ON t.TEAM_ID = h.TEAM_ID
JOIN away_results a ON t.TEAM_ID = a.TEAM_ID
ORDER BY home_court_edge DESC;

-- ---------------------------------------------------------------------
-- A6. Which players logged heavy minutes (top quartile of MIN_PLAYED)
--     but had below-average scoring efficiency (FG_PCT below the
--     league average)? Flags "high usage, low production" players.
-- ---------------------------------------------------------------------
WITH player_stats AS (
    SELECT
        PLAYER_NAME,
        AVG(MIN_PLAYED) AS avg_minutes,
        AVG(FG_PCT) AS avg_fg_pct,
        COUNT(*) AS games_played
    FROM games_details
    WHERE MIN_PLAYED IS NOT NULL AND FG_PCT IS NOT NULL
    GROUP BY PLAYER_NAME
    HAVING COUNT(*) >= 100
),
league_avg AS (
    SELECT AVG(FG_PCT) AS league_avg_fg_pct
    FROM games_details
    WHERE FG_PCT IS NOT NULL
),
minutes_threshold AS (
    -- 75th percentile of average minutes, approximated via NTILE
    SELECT avg_minutes
    FROM (
        SELECT avg_minutes, NTILE(4) OVER (ORDER BY avg_minutes) AS quartile
        FROM player_stats
    ) q
    WHERE quartile = 4
    ORDER BY avg_minutes ASC
    LIMIT 1
)
SELECT
    ps.PLAYER_NAME,
    ps.games_played,
    ROUND(ps.avg_minutes, 1) AS avg_minutes,
    ROUND(ps.avg_fg_pct, 3) AS avg_fg_pct,
    ROUND(la.league_avg_fg_pct, 3) AS league_avg_fg_pct
FROM player_stats ps
CROSS JOIN league_avg la
CROSS JOIN minutes_threshold mt
WHERE ps.avg_minutes >= mt.avg_minutes
  AND ps.avg_fg_pct < la.league_avg_fg_pct
ORDER BY ps.avg_minutes DESC;

-- ---------------------------------------------------------------------
-- A7. What is the longest winning streak for a given team
--     (example: TEAM_ID 1610612747 = Lakers)? Classic "gaps and
--     islands" problem solved with window functions.
-- ---------------------------------------------------------------------
WITH team_games AS (
    SELECT
        GAME_DATE_EST,
        CASE WHEN TEAM_ID_home = 1610612747 THEN HOME_TEAM_WINS
             ELSE 1 - HOME_TEAM_WINS END AS team_won
    FROM games
    WHERE TEAM_ID_home = 1610612747 OR TEAM_ID_away = 1610612747
),
flagged AS (
    SELECT
        GAME_DATE_EST,
        team_won,
        ROW_NUMBER() OVER (ORDER BY GAME_DATE_EST)
            - ROW_NUMBER() OVER (PARTITION BY team_won ORDER BY GAME_DATE_EST) AS streak_group
    FROM team_games
),
streaks AS (
    SELECT
        team_won,
        streak_group,
        COUNT(*) AS streak_length,
        MIN(GAME_DATE_EST) AS streak_start,
        MAX(GAME_DATE_EST) AS streak_end
    FROM flagged
    WHERE team_won = 1
    GROUP BY team_won, streak_group
)
SELECT streak_length, streak_start, streak_end
FROM streaks
ORDER BY streak_length DESC
LIMIT 1;
