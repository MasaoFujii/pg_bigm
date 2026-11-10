MODULE_big = pg_bigm
OBJS = bigm_op.o bigm_gin.o

EXTENSION = pg_bigm
DATA = pg_bigm--1.2--1.3.sql pg_bigm--1.2.sql pg_bigm--1.1--1.2.sql \
	pg_bigm--1.0--1.1.sql
PGFILEDESC = "pg_bigm - bigram matching"

REGRESS = pg_bigm pg_bigm_ja pg_bigm_signed pg_bigm_ja_signed

SIGNED_SQL = sql/pg_bigm_signed.sql sql/pg_bigm_ja_signed.sql
SIGNED_EXPECTED = expected/pg_bigm_signed.out expected/pg_bigm_ja_signed.out
EXTRA_CLEAN = $(SIGNED_SQL) $(SIGNED_EXPECTED)

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/pg_bigm
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif

# Run the same tests and compare against the same results for both opclasses.
# Replace the opclass name in expected output too, since psql echoes the SQL.
$(SIGNED_SQL): sql/%_signed.sql: $(srcdir)/sql/%.sql $(srcdir)/Makefile
	$(MKDIR_P) sql
	sed 's/gin_bigm_ops/gin_bigm_signed_ops/g' $< > $@

$(SIGNED_EXPECTED): expected/%_signed.out: $(srcdir)/expected/%.out $(srcdir)/Makefile
	$(MKDIR_P) expected
	sed 's/gin_bigm_ops/gin_bigm_signed_ops/g' $< > $@

check installcheck installcheck-trgm: $(SIGNED_SQL) $(SIGNED_EXPECTED)

installcheck-trgm: 
	$(pg_regress_installcheck) $(REGRESS_OPTS) load_trgm $(REGRESS)
