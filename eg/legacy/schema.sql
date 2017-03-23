CREATE TABLE metabase (
    guid VARCHAR NOT NULL,
    id INTEGER,
    updated INTEGER,
    report TEXT,
    fact TEXT,
    PRIMARY KEY ( guid )
);
