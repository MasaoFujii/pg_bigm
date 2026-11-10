-- complain if script is sourced in psql, rather than via ALTER EXTENSION
\echo Use "ALTER EXTENSION pg_bigm UPDATE TO '1.3'" to load this file. \quit

CREATE FUNCTION bigmtextcmp_signed(text, text)
RETURNS int4
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT IMMUTABLE;

-- Use the existing C function with the int4 return type required by GIN.
CREATE FUNCTION gin_bigm_compare_partial_int4(text, text, int2, internal)
RETURNS int4
AS 'MODULE_PATHNAME', 'gin_bigm_compare_partial'
LANGUAGE C IMMUTABLE STRICT;

-- Add an operator class with fixed signed-byte ordering.
CREATE OPERATOR CLASS gin_bigm_signed_ops
FOR TYPE text USING gin
AS
        OPERATOR        1       pg_catalog.~~ (text, text),
        OPERATOR        2       =% (text, text),
        FUNCTION        1       bigmtextcmp_signed (text, text),
        FUNCTION        2       gin_extract_value_bigm (text, internal),
        FUNCTION        3       gin_extract_query_bigm (text, internal, int2, internal, internal, internal, internal),
        FUNCTION        4       gin_bigm_consistent (internal, int2, text, int4, internal, internal, internal, internal),
        FUNCTION        5       gin_bigm_compare_partial_int4 (text, text, int2, internal),
        STORAGE         text;

DO $$
DECLARE
    pgversion INTEGER;
BEGIN
    SELECT current_setting('server_version_num')::INTEGER INTO pgversion;
    IF pgversion >= 90400 THEN
        ALTER OPERATOR FAMILY gin_bigm_signed_ops USING gin ADD
            FUNCTION        6    (text, text) gin_bigm_triconsistent (internal, int2, text, int4, internal, internal, internal);
    END IF;
    IF pgversion >= 90600 THEN
        EXECUTE 'ALTER FUNCTION bigmtextcmp_signed(text, text) PARALLEL SAFE';
        EXECUTE 'ALTER FUNCTION gin_bigm_compare_partial_int4(text, text, int2, internal) PARALLEL SAFE';
    END IF;
END;
$$;
