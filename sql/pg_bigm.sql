CREATE EXTENSION pg_bigm;

\pset null '(null)'

SET standard_conforming_strings = on;
DO $$
BEGIN
	IF current_setting('server_version_num')::int < 190000 THEN
		EXECUTE 'SET escape_string_warning = off';
	END IF;
END
$$;
SET enable_seqscan = off;
SET pg_bigm.enable_recheck = on;
SET pg_bigm.gin_key_limit = 0;
SET pg_bigm.similarity_limit = 0.02;

-- reduce noise
SET extra_float_digits TO 0;

-- tests for pg_bigm.last_update
SHOW pg_bigm.last_update;
SET pg_bigm.last_update = '2013.09.18';

-- tests for likequery
SELECT likequery(NULL);
SELECT likequery('');
SELECT likequery('  ');
SELECT likequery('aBc023#*^&');
SELECT likequery('\_%');

-- tests for show_bigm
SELECT show_bigm(NULL);
SELECT show_bigm('');
SELECT show_bigm('i');
SELECT show_bigm('ab');
SELECT show_bigm('aBc023$&^');
SELECT show_bigm('\_%');
SELECT show_bigm('  ');
SELECT show_bigm('pg_bigm improves performance by 200%');

-- tests for creation of full-text search index
CREATE TABLE test_bigm (col1 text, col2 text);
CREATE INDEX test_bigm_idx ON test_bigm
			 USING gin (col1 gin_bigm_ops, col2 gin_bigm_ops);

\copy test_bigm from 'data/bigm.csv' with csv

-- tests pg_gin_pending_stats

-- exclude pages column from the return values of only this call of
-- pg_gin_pending_stats(), in order to stabilize the result of
-- this regression test whatever block size is used in PostgreSQL server.
SELECT tuples FROM pg_gin_pending_stats('test_bigm_idx');
VACUUM;
SELECT * FROM pg_gin_pending_stats('test_bigm_idx');
SELECT * FROM pg_gin_pending_stats('test_bigm');
CREATE INDEX test_bigm_btree ON test_bigm USING btree (col2);
SELECT * FROM pg_gin_pending_stats('test_bigm_btree');
DROP INDEX test_bigm_btree;

-- tests for full-text search
EXPLAIN (COSTS off) SELECT * FROM test_bigm WHERE col1 LIKE likequery('a');
EXPLAIN (COSTS off) SELECT * FROM test_bigm WHERE col1 LIKE likequery('am');
EXPLAIN (COSTS off) SELECT * FROM test_bigm WHERE col1 LIKE likequery('XML');
EXPLAIN (COSTS off) SELECT * FROM test_bigm WHERE col1 LIKE likequery('bigm');

SELECT col1 FROM test_bigm WHERE col1 LIKE likequery(NULL);
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('');

SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('%');
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('\');
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('_');
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('\dx');
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('pg_bigm');
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('200%');
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('  ');

SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('Y');
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('pi');
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('GIN');
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('gin');
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('Tool');
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('performance');

-- check that the search results don't change if enable_recheck is disabled
-- in order to check that index full search is NOT executed
SET pg_bigm.enable_recheck = off;
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('Y');
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('pi');
SET pg_bigm.enable_recheck = on;

EXPLAIN (COSTS off) SELECT col1 FROM test_bigm WHERE col1 LIKE '%bigm%';
SELECT col1 FROM test_bigm WHERE col1 LIKE '%Tool%';
EXPLAIN (COSTS off) SELECT col1 FROM test_bigm WHERE col1 LIKE '%\%';
SELECT col1 FROM test_bigm WHERE col1 LIKE '%\%';
EXPLAIN (COSTS off) SELECT col1 FROM test_bigm WHERE col1 LIKE 'pg\___gm%';
SELECT col1 FROM test_bigm WHERE col1 LIKE 'pg\___gm%';

-- '_' wildcards require rechecking even with a single extracted bigram.
CREATE TABLE test_bigm_wildcard (name text);
INSERT INTO test_bigm_wildcard VALUES
	('a1'), ('ab'), ('abc'), ('a12345'), ('abcdef'), ('abcdefg'), ('b12345'),
	('a12'), ('abcd'), ('bc'), ('aabc'), ('_'), ('x_'), ('x_y'), ('x\'), ('x\y');
CREATE INDEX test_bigm_wildcard_idx ON test_bigm_wildcard
	USING gin (name gin_bigm_ops);
EXPLAIN (COSTS off)
SELECT name FROM test_bigm_wildcard WHERE name LIKE 'a_____';
SELECT name FROM test_bigm_wildcard WHERE name LIKE 'a_____' ORDER BY name;
SELECT name FROM test_bigm_wildcard WHERE name LIKE 'a_' ORDER BY name;
SELECT name FROM test_bigm_wildcard WHERE name LIKE '%1_' ORDER BY name;
SELECT name FROM test_bigm_wildcard WHERE name LIKE '%bc_' ORDER BY name;
SELECT name FROM test_bigm_wildcard WHERE name LIKE 'ab____' ORDER BY name;

-- Check leading wildcards and escaped characters.
SELECT name FROM test_bigm_wildcard WHERE name LIKE '_bc%' ORDER BY name;
SELECT name FROM test_bigm_wildcard WHERE name LIKE $$%\_%$$ ORDER BY name;
SELECT name FROM test_bigm_wildcard WHERE name LIKE $$%\\_$$ ORDER BY name;
SELECT name FROM test_bigm_wildcard WHERE name LIKE '%#_' ESCAPE '#' ORDER BY name;

-- Duplicate bigrams require rechecking even with a single distinct bigram.
-- '%aaa%' extracts only 'aa' after deduplication, but must not match 'aa'.
INSERT INTO test_bigm_wildcard VALUES ('aa'), ('aaa'), ('aaaa');
EXPLAIN (COSTS off)
SELECT name FROM test_bigm_wildcard WHERE name LIKE '%aaa%';
SELECT name FROM test_bigm_wildcard WHERE name LIKE '%aaa%' ORDER BY name;

DROP TABLE test_bigm_wildcard;

-- GIN searches with no extracted bigrams must include values with no index
-- keys and recheck each candidate against the LIKE pattern.
CREATE TABLE test_bigm_no_keys (name text);
INSERT INTO test_bigm_no_keys VALUES (NULL), (''), (' '), ('a'), ('ab');
CREATE INDEX test_bigm_no_keys_idx ON test_bigm_no_keys
	USING gin (name gin_bigm_ops);
EXPLAIN (COSTS off)
SELECT name FROM test_bigm_no_keys WHERE name LIKE '';
SELECT quote_nullable(name) FROM test_bigm_no_keys WHERE name LIKE '' ORDER BY name;
SELECT quote_nullable(name) FROM test_bigm_no_keys WHERE name LIKE '%' ORDER BY name;
SELECT quote_nullable(name) FROM test_bigm_no_keys WHERE name LIKE '_' ORDER BY name;
SELECT quote_nullable(name) FROM test_bigm_no_keys WHERE name LIKE '__' ORDER BY name;
DROP TABLE test_bigm_no_keys;

-- tests for pg_bigm.enable_recheck
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('trial');
SET pg_bigm.enable_recheck = off;
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('trial');

-- tests for pg_bigm.gin_key_limit
SELECT count(*) FROM test_bigm WHERE col1 LIKE likequery('she tore');
SET pg_bigm.gin_key_limit = 6;
SELECT count(*) FROM test_bigm WHERE col1 LIKE likequery('she tore');
SET pg_bigm.gin_key_limit = 5;
SELECT count(*) FROM test_bigm WHERE col1 LIKE likequery('she tore');
SET pg_bigm.gin_key_limit = 4;
SELECT count(*) FROM test_bigm WHERE col1 LIKE likequery('she tore');
SET pg_bigm.gin_key_limit = 3;
SELECT count(*) FROM test_bigm WHERE col1 LIKE likequery('she tore');
SET pg_bigm.gin_key_limit = 2;
SELECT count(*) FROM test_bigm WHERE col1 LIKE likequery('she tore');
SET pg_bigm.gin_key_limit = 1;
SELECT count(*) FROM test_bigm WHERE col1 LIKE likequery('she tore');

SET pg_bigm.enable_recheck = on;
SET pg_bigm.gin_key_limit = 0;

-- Key limits must not change LIKE or similarity results when rechecking
-- is enabled.
BEGIN;
CREATE TEMP TABLE test_bigm_key_limit (name text);
INSERT INTO test_bigm_key_limit VALUES ('ab'), ('xab'), ('ax');
CREATE INDEX test_bigm_key_limit_idx ON test_bigm_key_limit
	USING gin (name gin_bigm_ops);
SET LOCAL pg_bigm.enable_recheck = on;
SET LOCAL pg_bigm.similarity_limit = 0.3;
SET LOCAL pg_bigm.gin_key_limit = 1;

-- Reference results from sequential scans.
SET LOCAL enable_seqscan = on;
SET LOCAL enable_indexscan = off;
SET LOCAL enable_bitmapscan = off;
EXPLAIN (COSTS off)
SELECT name FROM test_bigm_key_limit WHERE name =% 'ab';
SELECT name FROM test_bigm_key_limit WHERE name LIKE 'ab%' ORDER BY name;
SELECT name FROM test_bigm_key_limit WHERE name =% 'ab' ORDER BY name;

-- GIN results must match the sequential scan results at each key limit.
SET LOCAL enable_seqscan = off;
SET LOCAL enable_indexscan = on;
SET LOCAL enable_bitmapscan = on;
EXPLAIN (COSTS off)
SELECT name FROM test_bigm_key_limit WHERE name LIKE 'ab%';
EXPLAIN (COSTS off)
SELECT name FROM test_bigm_key_limit WHERE name =% 'ab';
SELECT name FROM test_bigm_key_limit WHERE name LIKE 'ab%' ORDER BY name;
SELECT name FROM test_bigm_key_limit WHERE name =% 'ab' ORDER BY name;
SET LOCAL pg_bigm.gin_key_limit = 2;
SELECT name FROM test_bigm_key_limit WHERE name LIKE 'ab%' ORDER BY name;
SELECT name FROM test_bigm_key_limit WHERE name =% 'ab' ORDER BY name;
SET LOCAL pg_bigm.gin_key_limit = 0;
SELECT name FROM test_bigm_key_limit WHERE name LIKE 'ab%' ORDER BY name;
SELECT name FROM test_bigm_key_limit WHERE name =% 'ab' ORDER BY name;
ROLLBACK;

-- tests for backslash handling using explicit string literals
DO $$
BEGIN
	IF current_setting('server_version_num')::int < 190000 THEN
		EXECUTE 'SET standard_conforming_strings = off';
	END IF;
END
$$;
SELECT likequery($$\_%$$);
SELECT show_bigm($$\_%$$);
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery($$\$$);
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery($$\dx$$);
SELECT col1 FROM test_bigm WHERE col1 LIKE likequery('200%');

-- tests for full text search with multi-column index
-- keyword exists only in col1. Query on col2 must not return any rows.
EXPLAIN (COSTS off) SELECT * FROM test_bigm WHERE col2 LIKE likequery('queries');
SELECT * FROM test_bigm WHERE col2 LIKE likequery('queries');
-- keyword exists only in col2. All rows with keyword in col2 are returned.
EXPLAIN (COSTS off) SELECT * FROM test_bigm WHERE col2 LIKE likequery('meta');
SELECT * FROM test_bigm WHERE col2 LIKE likequery('meta');
-- keyword exists in both columns. Query on col1 must not return rows with keyword in col2 only.
EXPLAIN (COSTS off) SELECT * FROM test_bigm WHERE col1 LIKE likequery('bigm');
SELECT * FROM test_bigm WHERE col1 LIKE likequery('bigm');

-- tests for bigm_similarity
SELECT bigm_similarity('wow', NULL);
SELECT bigm_similarity('wow', '');

SELECT bigm_similarity('wow', 'WOWa ');
SELECT bigm_similarity('wow', ' WOW ');
SELECT bigm_similarity('wow', ' wow ');

SELECT bigm_similarity('---', '####---');

-- tests for text similarity serach
EXPLAIN (COSTS off) SELECT * FROM test_bigm WHERE col1 =% 'a';
EXPLAIN (COSTS off) SELECT * FROM test_bigm WHERE col1 =% 'am';
EXPLAIN (COSTS off) SELECT * FROM test_bigm WHERE col1 =% 'XML';
EXPLAIN (COSTS off) SELECT * FROM test_bigm WHERE col1 =% 'bigm';

SELECT col1 FROM test_bigm WHERE col1 =% NULL;
SELECT col1 FROM test_bigm WHERE col1 =% '';

SELECT col1 FROM test_bigm WHERE col1 =% '%';
SELECT col1 FROM test_bigm WHERE col1 =% $$\$$;
SELECT col1 FROM test_bigm WHERE col1 =% '_';
SELECT col1 FROM test_bigm WHERE col1 =% $$\dx$$;
SELECT col1 FROM test_bigm WHERE col1 =% '200%';
SELECT col1 FROM test_bigm WHERE col1 =% '  ';

SELECT count(*), min(bigm_similarity(col1, 'Y')) FROM test_bigm WHERE col1 =% 'Y';
SELECT count(*), max(bigm_similarity(col1, 'Y')) FROM test_bigm WHERE NOT col1 =% 'Y';
SELECT count(*), min(bigm_similarity(col1, 'pi')) FROM test_bigm WHERE col1 =% 'pi';
SELECT count(*), max(bigm_similarity(col1, 'pi')) FROM test_bigm WHERE NOT col1 =% 'pi';
SET pg_bigm.similarity_limit = 0.06;
SELECT count(*), min(bigm_similarity(col1, 'GIN')) FROM test_bigm WHERE col1 =% 'GIN';
SELECT count(*), max(bigm_similarity(col1, 'GIN')) FROM test_bigm WHERE NOT col1 =% 'GIN';
SELECT count(*), min(bigm_similarity(col1, 'gin')) FROM test_bigm WHERE col1 =% 'gin';
SELECT count(*), max(bigm_similarity(col1, 'gin')) FROM test_bigm WHERE NOT col1 =% 'gin';
SELECT count(*), min(bigm_similarity(col1, 'Tool')) FROM test_bigm WHERE col1 =% 'Tool';
SELECT count(*), max(bigm_similarity(col1, 'Tool')) FROM test_bigm WHERE NOT col1 =% 'Tool';
SELECT count(*), min(bigm_similarity(col1, 'performance')) FROM test_bigm WHERE col1 =% 'performance';
SELECT count(*), max(bigm_similarity(col1, 'performance')) FROM test_bigm WHERE NOT col1 =% 'performance';

-- Compare sequential and GIN scans at the similarity threshold endpoints.
-- A zero threshold matches every non-NULL value for non-NULL queries.
BEGIN;
CREATE TEMP TABLE test_bigm_similarity (id int, name text);
INSERT INTO test_bigm_similarity VALUES
	(1, 'abc'), (2, 'xyz'), (3, ''), (4, ' '), (5, NULL), (6, 'abc'), (7, 'ab');
CREATE INDEX test_bigm_similarity_idx ON test_bigm_similarity
	USING gin (name gin_bigm_ops);
CREATE TEMP TABLE test_bigm_similarity_queries (query_no int, search_text text);
INSERT INTO test_bigm_similarity_queries VALUES
	(1, 'abc'), (2, 'xyz'), (3, ''), (4, ' '), (5, NULL);
SET LOCAL pg_bigm.enable_recheck = on;
SET LOCAL pg_bigm.gin_key_limit = 0;

-- Evaluate the reference results without using the index.
SET LOCAL enable_seqscan = on;
SET LOCAL enable_indexscan = off;
SET LOCAL enable_bitmapscan = off;
SET LOCAL pg_bigm.similarity_limit = 0;
EXPLAIN (COSTS off)
SELECT id FROM test_bigm_similarity WHERE name =% 'abc';
SELECT quote_nullable(q.search_text) AS query,
	ARRAY(SELECT id FROM test_bigm_similarity
		  WHERE name =% q.search_text ORDER BY id) AS ids
FROM test_bigm_similarity_queries q
ORDER BY q.query_no;
SET LOCAL pg_bigm.similarity_limit = 1;
SELECT quote_nullable(q.search_text) AS query,
	ARRAY(SELECT id FROM test_bigm_similarity
		  WHERE name =% q.search_text ORDER BY id) AS ids
FROM test_bigm_similarity_queries q
ORDER BY q.query_no;

-- Evaluate the same queries using the GIN index.
SET LOCAL enable_seqscan = off;
SET LOCAL enable_indexscan = on;
SET LOCAL enable_bitmapscan = on;
SET LOCAL pg_bigm.similarity_limit = 0;
EXPLAIN (COSTS off)
SELECT id FROM test_bigm_similarity WHERE name =% 'abc';
SELECT quote_nullable(q.search_text) AS query,
	ARRAY(SELECT id FROM test_bigm_similarity
		  WHERE name =% q.search_text ORDER BY id) AS ids
FROM test_bigm_similarity_queries q
ORDER BY q.query_no;
SET LOCAL pg_bigm.similarity_limit = 1;
SELECT quote_nullable(q.search_text) AS query,
	ARRAY(SELECT id FROM test_bigm_similarity
		  WHERE name =% q.search_text ORDER BY id) AS ids
FROM test_bigm_similarity_queries q
ORDER BY q.query_no;

ROLLBACK;

-- tests for drop of pg_bigm
DROP EXTENSION pg_bigm CASCADE;
SELECT NOT EXISTS
	(SELECT 1
	 FROM pg_proc
	 WHERE proname = 'likequery'
	   AND pronargs = 1
	   AND proargtypes[0] = 'text'::regtype) AS missing;

-- end of tests
