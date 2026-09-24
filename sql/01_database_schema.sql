CREATE DATABASE nba_analytics;
USE nba_analytics;

-- 1) TEAMS — team master data, real primary key
CREATE TABLE teams (
    TEAM_ID             INT PRIMARY KEY,
    LEAGUE_ID           INT,
    MIN_YEAR            INT,
    MAX_YEAR            INT,
    ABBREVIATION        VARCHAR(10),
    NICKNAME            VARCHAR(50),
    YEARFOUNDED         INT,
    CITY                VARCHAR(50),
    ARENA               VARCHAR(100),
    ARENACAPACITY       INT NULL,
    OWNER               VARCHAR(100),
    GENERALMANAGER      VARCHAR(100),
    HEADCOACH           VARCHAR(100),
    DLEAGUEAFFILIATION  VARCHAR(100)
);

-- 2) PLAYERS — roster per season, composite key
CREATE TABLE players (
    PLAYER_NAME  VARCHAR(100),
    TEAM_ID      INT,
    PLAYER_ID    INT,
    SEASON       INT,
    PRIMARY KEY (PLAYER_ID, TEAM_ID, SEASON),
    FOREIGN KEY (TEAM_ID) REFERENCES teams(TEAM_ID)
);

-- 3) GAMES — one row per game, game-level box score
CREATE TABLE games (
    id                BIGINT AUTO_INCREMENT PRIMARY KEY,
    GAME_DATE_EST     DATE,
    GAME_ID           INT,
    GAME_STATUS_TEXT  VARCHAR(20),
    HOME_TEAM_ID      INT,
    VISITOR_TEAM_ID   INT,
    SEASON            INT,
    TEAM_ID_home      INT,
    PTS_home          DECIMAL(5,1) NULL,
    FG_PCT_home       DECIMAL(5,3) NULL,
    FT_PCT_home       DECIMAL(5,3) NULL,
    FG3_PCT_home      DECIMAL(5,3) NULL,
    AST_home          DECIMAL(5,1) NULL,
    REB_home          DECIMAL(5,1) NULL,
    TEAM_ID_away      INT,
    PTS_away          DECIMAL(5,1) NULL,
    FG_PCT_away       DECIMAL(5,3) NULL,
    FT_PCT_away       DECIMAL(5,3) NULL,
    FG3_PCT_away      DECIMAL(5,3) NULL,
    AST_away          DECIMAL(5,1) NULL,
    REB_away          DECIMAL(5,1) NULL,
    HOME_TEAM_WINS    TINYINT,
    INDEX idx_game_id (GAME_ID),
    INDEX idx_season (SEASON)
);

-- 4) GAMES_DETAILS — one row per player per game (the core stats table)
CREATE TABLE games_details (
    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
    GAME_ID             INT,
    TEAM_ID             INT,
    TEAM_ABBREVIATION   VARCHAR(10),
    TEAM_CITY           VARCHAR(50),
    PLAYER_ID           INT,
    PLAYER_NAME         VARCHAR(100),
    NICKNAME            VARCHAR(50) NULL,
    START_POSITION      VARCHAR(5) NULL,
    COMMENT             VARCHAR(100) NULL,
    MIN                 VARCHAR(10) NULL,
    FGM                 DECIMAL(4,1) NULL,
    FGA                 DECIMAL(4,1) NULL,
    FG_PCT              DECIMAL(5,3) NULL,
    FG3M                DECIMAL(4,1) NULL,
    FG3A                DECIMAL(4,1) NULL,
    FG3_PCT             DECIMAL(5,3) NULL,
    FTM                 DECIMAL(4,1) NULL,
    FTA                 DECIMAL(4,1) NULL,
    FT_PCT              DECIMAL(5,3) NULL,
    OREB                DECIMAL(4,1) NULL,
    DREB                DECIMAL(4,1) NULL,
    REB                 DECIMAL(4,1) NULL,
    AST                 DECIMAL(4,1) NULL,
    STL                 DECIMAL(4,1) NULL,
    BLK                 DECIMAL(4,1) NULL,
    TOV                 DECIMAL(4,1) NULL,
    PF                  DECIMAL(4,1) NULL,
    PTS                 DECIMAL(4,1) NULL,
    PLUS_MINUS          DECIMAL(5,1) NULL,
    INDEX idx_game_player (GAME_ID, PLAYER_ID),
    INDEX idx_player (PLAYER_ID)
);

-- 5) RANKING — daily standings snapshot per team
CREATE TABLE ranking (
    id             BIGINT AUTO_INCREMENT PRIMARY KEY,
    TEAM_ID        INT,
    LEAGUE_ID      INT,
    SEASON_ID      INT,
    STANDINGSDATE  DATE,
    CONFERENCE     VARCHAR(10),
    TEAM           VARCHAR(50),
    G              INT,
    W              INT,
    L              INT,
    W_PCT          DECIMAL(4,3),
    HOME_RECORD    VARCHAR(10),
    ROAD_RECORD    VARCHAR(10),
    RETURNTOPLAY   VARCHAR(10) NULL,
    INDEX idx_team_date (TEAM_ID, STANDINGSDATE)
);
