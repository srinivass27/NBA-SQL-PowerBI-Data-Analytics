-- =====================================================================
-- NBA PLAYER PERFORMANCE ANALYSIS
-- 02_data_cleaning.sql
-- Purpose: Identify and fix data-quality issues found during profiling
--          (see Step 1 dataset understanding notes in the README).
-- Tables: teams, players, games, games_details, ranking
-- =====================================================================

USE nba_analytics;

-- =====================================================================
-- SECTION 1: NULL VALUE CHECKS
-- =====================================================================

-- 1.1 games: how many rows are missing score/box-score fields?
SELECT
    COUNT(*) AS total_rows,
    SUM(PTS_home IS NULL)     AS missing_pts_home,
    SUM(PTS_away IS NULL)     AS missing_pts_away,
    SUM(FG_PCT_home IS NULL)  AS missing_fg_pct_home,
    SUM(FT_PCT_home IS NULL)  AS missing_ft_pct_home,
    SUM(FG3_PCT_home IS NULL) AS missing_fg3_pct_home,
    SUM(AST_home IS NULL)     AS missing_ast_home,
    SUM(REB_home IS NULL)     AS missing_reb_home
FROM games;

-- 1.2 games_details: NULL counts per stat column
SELECT
    COUNT(*) AS total_rows,
    SUM(MIN IS NULL)        AS missing_min,
    SUM(PTS IS NULL)        AS missing_pts,
    SUM(REB IS NULL)        AS missing_reb,
    SUM(AST IS NULL)        AS missing_ast,
    SUM(FG_PCT IS NULL)     AS missing_fg_pct,
    SUM(START_POSITION IS NULL) AS missing_start_position,
    SUM(PLUS_MINUS IS NULL) AS missing_plus_minus,
    SUM(COMMENT IS NOT NULL) AS rows_with_dnp_comment
FROM games_details;

-- 1.3 ranking: confirm RETURNTOPLAY is mostly unused (safe to ignore in analysis)
SELECT
    COUNT(*) AS total_rows,
    SUM(RETURNTOPLAY IS NULL) AS missing_returntoplay
FROM ranking;

-- 1.4 teams: confirm which teams are missing arena capacity
SELECT TEAM_ID, ABBREVIATION, CITY, ARENA, ARENACAPACITY
FROM teams
WHERE ARENACAPACITY IS NULL;

-- 1.5 players: sanity check (should return 0 rows, table has no NULL-prone columns)
SELECT * FROM players
WHERE PLAYER_NAME IS NULL OR TEAM_ID IS NULL OR PLAYER_ID IS NULL OR SEASON IS NULL;


-- =====================================================================
-- SECTION 2: DUPLICATE RECORD CHECKS
-- =====================================================================

-- 2.1 games: find GAME_IDs that appear more than once
SELECT GAME_ID, COUNT(*) AS occurrences
FROM games
GROUP BY GAME_ID
HAVING COUNT(*) > 1;

-- 2.2 games_details: find (GAME_ID, PLAYER_ID) pairs that appear more than once
SELECT GAME_ID, PLAYER_ID, COUNT(*) AS occurrences
FROM games_details
GROUP BY GAME_ID, PLAYER_ID
HAVING COUNT(*) > 1;

-- 2.3 players: confirm no duplicate (PLAYER_ID, TEAM_ID, SEASON) combos
--     (guaranteed by the composite PRIMARY KEY, but verified here for completeness)
SELECT PLAYER_ID, TEAM_ID, SEASON, COUNT(*) AS occurrences
FROM players
GROUP BY PLAYER_ID, TEAM_ID, SEASON
HAVING COUNT(*) > 1;


-- =====================================================================
-- SECTION 3: REMOVE DUPLICATES
-- Approach: for each duplicate key, keep the row with the smallest
-- surrogate id (the earliest-loaded copy) and delete the rest.
-- This is the simplest, most transparent rule for a portfolio project;
-- it assumes duplicate rows carry the same information (confirmed by
-- the profiling step, where full-row duplicates were 0 but key-level
-- duplicates existed).
-- =====================================================================

-- 3.1 De-duplicate games on GAME_ID
DELETE g1 FROM games g1
INNER JOIN games g2
    ON g1.GAME_ID = g2.GAME_ID
   AND g1.id > g2.id;

-- 3.2 De-duplicate games_details on (GAME_ID, PLAYER_ID)
DELETE gd1 FROM games_details gd1
INNER JOIN games_details gd2
    ON gd1.GAME_ID = gd2.GAME_ID
   AND gd1.PLAYER_ID = gd2.PLAYER_ID
   AND gd1.id > gd2.id;

-- 3.3 Lock in uniqueness going forward so this can't silently reappear
ALTER TABLE games
    ADD UNIQUE KEY uq_games_game_id (GAME_ID);

ALTER TABLE games_details
    ADD UNIQUE KEY uq_gd_game_player (GAME_ID, PLAYER_ID);


-- =====================================================================
-- SECTION 4: CONVERT MIN (TEXT "MM:SS") TO A NUMERIC MINUTES COLUMN
-- Raw MIN values look like '18:06' (minutes:seconds) or occasionally
-- a plain integer string. We add a decimal column so it can be
-- aggregated (AVG, SUM) directly in SQL and Power BI.
-- =====================================================================

ALTER TABLE games_details
    ADD COLUMN MIN_PLAYED DECIMAL(5,2) NULL AFTER MIN;

UPDATE games_details
SET MIN_PLAYED = CASE
    WHEN MIN IS NULL THEN NULL
    WHEN MIN LIKE '%:%' THEN
        CAST(SUBSTRING_INDEX(MIN, ':', 1) AS DECIMAL(5,2))
        + CAST(SUBSTRING_INDEX(MIN, ':', -1) AS DECIMAL(5,2)) / 60
    ELSE CAST(MIN AS DECIMAL(5,2))
END;

-- Verify: any rows where conversion failed and left NULL despite MIN being present?
SELECT COUNT(*) AS conversion_failures
FROM games_details
WHERE MIN IS NOT NULL AND MIN_PLAYED IS NULL;


-- =====================================================================
-- SECTION 5: INVALID NUMERICAL VALUES
-- =====================================================================

-- 5.1 Negative stats should not exist (points, rebounds, assists, etc.)
SELECT *
FROM games_details
WHERE PTS < 0 OR REB < 0 OR AST < 0 OR STL < 0 OR BLK < 0
   OR TOV < 0 OR PF < 0 OR FGM < 0 OR FGA < 0;

-- 5.2 Percentages must fall between 0 and 1 (or be NULL)
SELECT *
FROM games_details
WHERE FG_PCT  NOT BETWEEN 0 AND 1 AND FG_PCT  IS NOT NULL
   OR FG3_PCT NOT BETWEEN 0 AND 1 AND FG3_PCT IS NOT NULL
   OR FT_PCT  NOT BETWEEN 0 AND 1 AND FT_PCT  IS NOT NULL;

SELECT *
FROM games
WHERE FG_PCT_home  NOT BETWEEN 0 AND 1 AND FG_PCT_home  IS NOT NULL
   OR FG3_PCT_home NOT BETWEEN 0 AND 1 AND FG3_PCT_home IS NOT NULL
   OR FT_PCT_home  NOT BETWEEN 0 AND 1 AND FT_PCT_home  IS NOT NULL
   OR FG_PCT_away  NOT BETWEEN 0 AND 1 AND FG_PCT_away  IS NOT NULL
   OR FG3_PCT_away NOT BETWEEN 0 AND 1 AND FG3_PCT_away IS NOT NULL
   OR FT_PCT_away  NOT BETWEEN 0 AND 1 AND FT_PCT_away  IS NOT NULL;

-- 5.3 Logical impossibilities: makes cannot exceed attempts
SELECT *
FROM games_details
WHERE FGM > FGA OR FG3M > FG3A OR FTM > FTA;

-- 5.4 Rebounds should add up: OREB + DREB should equal REB (allow NULLs)
SELECT *
FROM games_details
WHERE OREB IS NOT NULL AND DREB IS NOT NULL AND REB IS NOT NULL
  AND (OREB + DREB) <> REB;

-- 5.5 A team cannot play itself
SELECT *
FROM games
WHERE HOME_TEAM_ID = VISITOR_TEAM_ID;

-- 5.6 ranking: games played should equal wins + losses
SELECT *
FROM ranking
WHERE G <> (W + L);

-- 5.7 ranking: win percentage should be consistent with W and G
SELECT *
FROM ranking
WHERE G > 0
  AND ABS(W_PCT - (W / G)) > 0.01;


-- =====================================================================
-- SECTION 6: MISSING / ORPHAN TEAM INFORMATION (referential integrity)
-- These checks find rows that reference a TEAM_ID that doesn't exist
-- in the teams dimension table -- important before building Power BI
-- relationships, since orphan keys break joins silently.
-- =====================================================================

-- 6.1 players.csv rows whose TEAM_ID has no match in teams
SELECT p.*
FROM players p
LEFT JOIN teams t ON p.TEAM_ID = t.TEAM_ID
WHERE t.TEAM_ID IS NULL;

-- 6.2 games_details rows whose TEAM_ID has no match in teams
SELECT gd.*
FROM games_details gd
LEFT JOIN teams t ON gd.TEAM_ID = t.TEAM_ID
WHERE t.TEAM_ID IS NULL;

-- 6.3 games rows whose HOME_TEAM_ID or VISITOR_TEAM_ID has no match in teams
SELECT g.*
FROM games g
LEFT JOIN teams th ON g.HOME_TEAM_ID = th.TEAM_ID
LEFT JOIN teams ta ON g.VISITOR_TEAM_ID = ta.TEAM_ID
WHERE th.TEAM_ID IS NULL OR ta.TEAM_ID IS NULL;

-- 6.4 ranking rows whose TEAM_ID has no match in teams
SELECT r.*
FROM ranking r
LEFT JOIN teams t ON r.TEAM_ID = t.TEAM_ID
WHERE t.TEAM_ID IS NULL;


-- =====================================================================
-- SECTION 7: HANDLING "DID NOT PLAY" ROWS IN games_details
-- 109,690 rows have every stat column NULL. The COMMENT column
-- explains why (DNP - Coach's Decision, Injury/Illness, etc.).
-- We do NOT delete these rows -- they are valid records showing a
-- player was on the roster but did not play, which matters for
-- questions like "games missed due to injury". We simply make sure
-- downstream analysis queries exclude them explicitly with
-- WHERE MIN_PLAYED IS NOT NULL (or PTS IS NOT NULL) where relevant.
-- =====================================================================

-- Confirm the 109,690-ish rows line up with a non-null COMMENT
SELECT
    SUM(CASE WHEN PTS IS NULL AND COMMENT IS NOT NULL THEN 1 ELSE 0 END) AS dnp_with_reason,
    SUM(CASE WHEN PTS IS NULL AND COMMENT IS NULL THEN 1 ELSE 0 END)     AS dnp_without_reason
FROM games_details;


-- =====================================================================
-- SECTION 8: FINAL SANITY CHECK
-- Re-run the row counts after cleaning to document the before/after
-- in the README's "Data Cleaning" section.
-- =====================================================================

SELECT 'teams' AS table_name, COUNT(*) AS row_count FROM teams
UNION ALL
SELECT 'players', COUNT(*) FROM players
UNION ALL
SELECT 'games', COUNT(*) FROM games
UNION ALL
SELECT 'games_details', COUNT(*) FROM games_details
UNION ALL
SELECT 'ranking', COUNT(*) FROM ranking;
