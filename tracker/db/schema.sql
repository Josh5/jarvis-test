DROP TABLE request;
CREATE TABLE request (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sid TEXT,
    debug_level INTEGER,
    app_name TEXT,
    username TEXT,
    group_list TEXT,
    dataset TEXT,
    dataset_type TEXT(1),
    action TEXT,
    params TEXT,
    in_nrows INTEGER,
    out_nrows INTEGER,
    start_time JULIAN,
    duration_ms INTEGER
);

DROP TABLE login;
CREATE TABLE login (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sid TEXT,
    app_name TEXT,
    username TEXT,
    logged_in INTEGER,
    error_string TEXT,
    group_list TEXT,
    address TEXT,
    start_time JULIAN
);

DROP TABLE error;
CREATE TABLE error (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sid TEXT,
    app_name TEXT,
    username TEXT,
    group_list TEXT,
    dataset TEXT,
    action TEXT,
    params TEXT,
    post_body TEXT,
    message TEXT,
    start_time JULIAN,
    http_response_code INTEGER
);

CREATE INDEX request_start_time_idx on request (start_time);

DROP TABLE calendar;
CREATE TABLE calendar (
    the_date JULIAN NOT NULL PRIMARY KEY,
    is_weekday INTEGER,
    year INTEGER,
    quarter INTEGER,
    month INTEGER,
    day INTEGER,
    day_of_week INTEGER,
    week INTEGER
);

DROP TABLE day_interval;
CREATE TABLE day_interval (
    interval FLOAT NOT NULL PRIMARY KEY,
    hour INTEGER,
    hour_minute INTEGER,
    is_minute INTEGER,
    is_five_minute INTEGER,
    is_fifteen_minute INTEGER
);

CREATE INDEX day_interval_15_idx ON day_interval (is_fifteen_minute);
CREATE INDEX day_interval_5_idx ON day_interval (is_five_minute);

DROP TABLE tracker_user;
CREATE TABLE tracker_user (
    username VARCHAR (50) NOT NULL PRIMARY KEY,
    password VARCHAR (50) NOT NULL,
    user_group VARCHAR (50) NOT NULL
);
