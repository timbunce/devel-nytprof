/* vim: ts=2 sw=2 sts=0 noexpandtab:
 * ************************************************************************
 * This file is part of the Devel::NYTProf package.
 * Copyright 2008 Adam J. Kaplan, The New York Times Company.
 * Copyright 2008 Tim Bunce, Ireland.
 * Released under the same terms as Perl 5.8
 * See http://search.cpan.org/dist/Devel-NYTProf/
 *
 * Contributors:
 * Adam Kaplan, akaplan at nytimes.com
 * Tim Bunce, http://www.tim.bunce.name and http://blog.timbunce.org
 * Steve Peters, steve at fisharerojo.org
 *
 * ************************************************************************
 * $Id$
 * ************************************************************************
 */
#define PERL_NO_GET_CONTEXT		/* we want efficiency */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#ifndef NO_PPPORT_H
#   define NEED_my_snprintf
#   include "ppport.h"
#endif
#if !defined(OutCopFILE)
#    define OutCopFILE CopFILE
#endif

#if (PERL_VERSION < 8) || ((PERL_VERSION == 8) && (PERL_SUBVERSION < 8))
/* If we're using DB::DB() instead of opcode redirection with an old perl
 * then PL_curcop in DB() will refer to the DB() wrapper in Devel/NYTProf.pm
 * so we'd have to crawl the stack to find the right cop. However, for some
 * reason that I don't pretend to understand the folowing expression works:
 */
#define PL_curcop_nytprof (use_db_sub ? ((cxstack + cxstack_ix)->blk_oldcop) : PL_curcop)
#else
#define PL_curcop_nytprof PL_curcop
#endif

#ifndef OP_NAME	/* for perl 5.6 */
#define OP_NAME "<?>"
#endif
#define OP_NAME_safe(op) ((op) ? OP_NAME(op) : "NULL")

#ifdef I_SYS_TIME
#include <sys/time.h>
#endif
#include <stdio.h>
#ifdef HAS_STDIO_EXT_H
#include <stdio_ext.h>
#else
#  ifndef WIN32
#    warning "Not using stdio_ext.h. Add it to INCLUDE path and recompile with -DHAS_STDIO_EXT_H to use it."
#  endif
#endif

#ifdef HASFPURGE
#define FPURGE(file) fpurge(file)
#define HAS_FPURGE_BOOL 1
#elif defined(HAS_FPURGE)
#define FPURGE(file) _fpurge(file)
#define HAS_FPURGE_BOOL 1
#elif defined(HAS__FPURGE)
#define FPURGE(file) __fpurge(file)
#define HAS_FPURGE_BOOL 1
#else
#define FPURGE(file)
#define HAS_FPURGE_BOOL 0
#  ifndef WIN32
#    warning "No fpurge function found -- risk of corrupted profile when forking"
#  endif
#endif

/* Hash table definitions */
#define MAX_HASH_SIZE 512

typedef struct hash_entry {
	unsigned int id;
	void* next_entry;
	char* key;
	unsigned int key_len;
	unsigned int eval_fid;
	unsigned int eval_line_num;
	unsigned int file_size;
	unsigned int file_mtime;
	char *key_abs;
	void* next_inserted; /* linked list in insertion order */
} Hash_entry;

typedef struct hash_table {
	Hash_entry** table;
	unsigned int size;
	Hash_entry* first_inserted;
	Hash_entry* last_inserted;
} Hash_table;

static Hash_table hashtable = { NULL, MAX_HASH_SIZE, NULL, NULL };
/* END Hash table definitions */

/* defaults */
static FILE* out;
static FILE* in;

/* options and overrides */
static char PROF_output_file[MAXPATHLEN+1] = "nytprof.out";
static bool embed_fid_line = 0;
static bool usecputime = 0;
static int use_db_sub = 0;
static int profile_begin = 0;   /* profile at once, ie compile time */
static int profile_blocks = 1;	/* block and sub *exclusive* times */
static int profile_subs = 1;    /* sub *inclusive* times */
static int profile_leave = 1;   /* correct block end timing */
static int profile_zero = 0;    /* don't do timing, all times are zero */
static int trace_level = 0;

/* time tracking */
static struct tms start_ctime, end_ctime;
#ifdef HAS_CLOCK_GETTIME
   /* http://webnews.giga.net.tw/article//mailing.freebsd.performance/710 */
   typedef struct timespec time_of_day_t;   
#  ifdef CLOCK_MONOTONIC
#    define CLOCK_GETTIME(ts) clock_gettime(CLOCK_MONOTONIC, ts)
#  else
#    define CLOCK_GETTIME(ts) clock_gettime(CLOCK_REALTIME, ts)
#  endif
#  define CLOCKS_PER_TICK 10000000 /* 10 million - 100ns */
#  define get_time_of_day(into) if (!profile_zero) CLOCK_GETTIME(&into)
#  define get_ticks_between(s, e, ticks, overflow) STMT_START { \
     overflow = 0; \
     ticks = ((e.tv_sec - s.tv_sec) * CLOCKS_PER_TICK + (e.tv_nsec / 100) - (s.tv_nsec / 100)); \
   } STMT_END
#else
#ifdef HAS_GETTIMEOFDAY
   typedef struct timeval time_of_day_t;
#  define CLOCKS_PER_TICK 1000000 /* 1 million */
#  define get_time_of_day(into) if (!profile_zero) gettimeofday(&into, NULL)
#  define get_ticks_between(s, e, ticks, overflow) STMT_START { \
		overflow = 0; \
		ticks = ((e.tv_sec - s.tv_sec) * CLOCKS_PER_TICK + e.tv_usec - s.tv_usec); \
	} STMT_END
#else
   static int (*u2time)(pTHX_ UV *) = 0;
   typedef UV time_of_day_t[2];
#  define CLOCKS_PER_TICK 1000000 /* 1 million */
#  define get_time_of_day(into) if (!profile_zero) (*u2time)(aTHX_ into)
#  define get_ticks_between(s, e, ticks, overflow)  STMT_START { \
		overflow = 0; \
		ticks = ((e[0] - s[0]) * CLOCKS_PER_TICK + e[1] - s[1]); \
	} STMT_END
#endif
#endif
static time_of_day_t start_time;
static time_of_day_t end_time;

static unsigned int last_executed_line;
static unsigned int last_executed_fid;
static        char *last_executed_fileptr;
static unsigned int last_block_line;
static unsigned int last_sub_line;
static unsigned int is_profiling;
static Pid_t last_pid;
static NV cumulative_overhead_ticks = 0.0;
static NV cumulative_subr_secs = 0.0;

static unsigned int ticks_per_sec = 0; /* 0 forces error if not set */

/* prototypes */
static void write_cached_fids();
void output_header(pTHX);
unsigned int get_file_id(pTHX_ char*, STRLEN, int);
void output_int(unsigned int);
void DB_stmt(pTHX_ OP *op);
void set_option(const char*, const char*);
static int enable_profile(pTHX);
static int disable_profile(pTHX);
static void finish_profile(pTHX);
void open_output_file(pTHX_ char *);
int reinit_if_forked(pTHX);
void write_sub_line_ranges(pTHX_ int fids_only);
void write_sub_callers(pTHX);
HV *load_profile_data_from_stream();
AV *store_profile_line_entry(pTHX_ SV *rvav, unsigned int line_num, 
															NV time, int count, unsigned int fid);

/* copy of original contents of PL_ppaddr */
OP * (CPERLscope(**PL_ppaddr_orig))(pTHX);
#define run_original_op(type) CALL_FPTR(PL_ppaddr_orig[type])(aTHX)
OP *pp_entersub_profiler(pTHX);
OP *pp_leaving_profiler(pTHX);
HV *sub_callers_hv;

/* macros for outputing profile data */
#define OUTPUT_PID() STMT_START { \
	assert(out != NULL); fputc('P', out); output_int(getpid()); output_int(getppid()); \
} STMT_END

#define END_OUTPUT_PID(pid) STMT_START { \
	assert(out != NULL); fputc('p', out); output_int(pid); fflush(out); \
} STMT_END


/***********************************
 * Devel::NYTProf Functions        *
 ***********************************/

/**
 * output file header
 */
void
output_header(pTHX) {
	SV *sv;
	time_t basetime = PL_basetime;

	assert(out != NULL);
	/* File header with "magic" string, with file major and minor version */
	fprintf(out, "NYTProf %d %d\n", 1, 2);
	/* Human readable comments and attributes follow
	 * comments start with '#', end with '\n', and are discarded
	 * attributes start with ':', a word, '=', then the value, then '\n'
	 */
	fprintf(out, "# Perl profile database. Generated by Devel::NYTProf on %s",
		ctime(&basetime)); /* uses \n from ctime to terminate line */

	/* XXX add options, $0, etc, but beware of embedded newlines */
	/* XXX would be good to adopt a proper charset & escaping for these */
	fprintf(out, ":%s=%lu\n",      "basetime",      (unsigned long)PL_basetime); /* $^T */
	fprintf(out, ":%s=%s\n",       "xs_version",    XS_VERSION);
	fprintf(out, ":%s=%d.%d.%d\n", "perl_version",  PERL_REVISION, PERL_VERSION, PERL_SUBVERSION);
	fprintf(out, ":%s=%u\n",       "ticks_per_sec", ticks_per_sec);
	/* $0 - application name */
	mg_get(sv = get_sv("0",GV_ADDWARN));
	fprintf(out, ":%s=%s\n",       "application", SvPV_nolen(sv));

	if (0)fprintf(out, ":%s=%lu\n",       "nv_size", sizeof(NV));

	OUTPUT_PID();

	write_cached_fids(); /* empty initially, non-empty after fork */

	fflush(out);
}

/**
 * An implementation of the djb2 hash function by Dan Bernstein.
 */
unsigned long
hash (char* _str, unsigned int len) {
	char* str = _str;
	unsigned long hash = 5381;

	while (len--) {
		hash = ((hash << 5) + hash) + *str++; /* hash * 33 + c */
	}
	return hash;
}

/**
 * Fetch/Store on hash table.  entry must always be defined. 
 * hash_op will find hash_entry in the hash table.  
 * hash_entry not in table, insert is false: returns NULL
 * hash_entry not in table, insert is true: inserts hash_entry and returns hash_entry
 * hash_entry in table, insert IGNORED: returns pointer to the actual hash entry
 */
char
hash_op (Hash_entry entry, Hash_entry** retval, bool insert) {
	static int next_fid = 1;	/* 0 is reserved */
	unsigned long h = hash(entry.key, entry.key_len) % hashtable.size;

	Hash_entry* found = hashtable.table[h];
	while(NULL != found) {

		if (found->key_len == entry.key_len && 
				strnEQ(found->key, entry.key, entry.key_len)) {
			*retval = found;
			return 0;
		}

		if (NULL == (Hash_entry*)found->next_entry) {
			if (insert) {

				Hash_entry* e;
				Newz(0, e, 1, Hash_entry);
				e->id = next_fid++;
				e->next_entry = NULL;
				e->key_len = entry.key_len;
				e->key = (char*)safemalloc(sizeof(char) * e->key_len + 1);
				e->key[e->key_len] = '\0';
				strncpy(e->key, entry.key, e->key_len);
				found->next_entry = e;
				*retval = (Hash_entry*)found->next_entry;
				if (hashtable.last_inserted)
					hashtable.last_inserted->next_inserted = e;
				hashtable.last_inserted = e;
				return 1;
			} else {
				*retval = NULL;
				return -1;
			}
		}
		found = (Hash_entry*)found->next_entry;
	}

	if (insert) {
		Hash_entry* e;
		Newz(0, e, 1, Hash_entry);
		e->id = next_fid++;
		e->next_entry = NULL;
		e->key_len = entry.key_len;
		e->key = (char*)safemalloc(sizeof(char) * e->key_len + 1);
		e->key[e->key_len] = '\0';
		strncpy(e->key, entry.key, e->key_len);

		*retval =	hashtable.table[h] = e;

		if (!hashtable.first_inserted)
			hashtable.first_inserted = e;
		if (hashtable.last_inserted)
			hashtable.last_inserted->next_inserted = e;
		hashtable.last_inserted = e;

		return 1;
	}

	*retval = NULL;
	return -1;
}


static void
emit_fid (Hash_entry *found) {
	char  *file_name     = found->key;
	STRLEN file_name_len = found->key_len;
	if (found->key_abs) {
		file_name = found->key_abs;
		file_name_len = strlen(file_name);
	}
	fputc('@', out);
	output_int(found->id);
	output_int(found->eval_fid);
	output_int(found->eval_line_num);
	output_int(0); /* flags/future use */
	output_int(found->file_size);
	output_int(found->file_mtime);
	while (file_name_len--)
		fputc(*file_name++, out);
	fputc('\n', out);
}


static void
write_cached_fids() {
	Hash_entry *e = hashtable.first_inserted;
	while (e) {
		emit_fid(e);
		e = (Hash_entry *)e->next_inserted;
	}
}


/**
 * Return a unique persistent id number for a file.
 * If file name has not been seen before
 * then, if create_new is false it returns 0 otherwise it
 * assigns a new id and outputs the file and id to the stream.
 * If the file name is a synthetic name for an eval then
 * get_file_id recurses to process the 'embedded' file name first.
 */
unsigned int
get_file_id(pTHX_ char* file_name, STRLEN file_name_len, int create_new) {

	Hash_entry entry, *found;

	/* AutoLoader adds some information to Perl's internal file name that we have
	   to remove or else the file path will be borked */
	if (')' == file_name[file_name_len - 1]) {
		char* new_end = strstr(file_name, " (autosplit ");
		if (new_end)
			file_name_len = new_end - file_name;
	}
	entry.key = file_name;
	entry.key_len = file_name_len;

	if (1 == hash_op(entry, &found, create_new)) {	/* inserted new entry */

		/* if this is a synthetic filename for an 'eval'
		 * ie "(eval 42)[/some/filename.pl:line]"
		 * then ensure we've already generated an id for the underlying
		 * filename
		 */
		if ('(' == file_name[0] && ']' == file_name[file_name_len-1]) {
			char *start = strchr(file_name, '[');
			const char *colon = ":";
			/* can't use strchr here (not nul terminated) so use rninstr */
			char *end = rninstr(file_name, file_name+file_name_len-1, colon, colon+1);

			if (!start || !end || start > end) {
				warn("Unsupported filename syntax '%s'", file_name);
				return 0;
			}
			++start; /* move past [ */
			found->eval_fid = get_file_id(aTHX_ start, end - start, create_new);	/* recurse */
			found->eval_line_num = atoi(end+1);
		}

		/* determine absolute path if file_name is relative */
		found->key_abs = NULL;
		if (!found->eval_fid && *file_name != '/') {
			char file_name_abs[MAXPATHLEN * 2];
			/* Note that the current directory may have changed
			 * between loading the file and profiling it.
			 * We don't use realpath() or similar here because we want to
			 * keep the of symlinks etc. as the program saw them.
			 */
			if (!getcwd(file_name_abs, sizeof(file_name_abs))) {
				warn("getcwd: %s\n", strerror(errno)); /* eg permission */
			}
			else if (strNE(file_name_abs, "/")) {
				if (strnEQ(file_name, "./", 2))
					++file_name;
				else
					strcat(file_name_abs, "/");
				strncat(file_name_abs, file_name, file_name_len);
				found->key_abs = strdup(file_name_abs);
			}
		}

		emit_fid(found);

		if (trace_level) {
			/* including last_executed_fid can be handy for tracking down how
			 * a file got loaded */
			if (found->eval_fid)
				warn("New fid %2u (after %2u:%-4u): %.*s (eval fid %u line %u)\n",
					found->id, last_executed_fid, last_executed_line,
					found->key_len, found->key, found->eval_fid, found->eval_line_num);
		  else
				warn("New fid %2u (after %2u:%-4u): %.*s %s\n",
					found->id, last_executed_fid, last_executed_line,
					found->key_len, found->key, (found->key_abs) ? found->key_abs : "");
		}
	}
  else if (trace_level >= 4) {
		if (found)
		     warn("fid %d: %.*s\n",   found->id, found->key_len, found->key);
		else warn("fid %d: %.*s NOT FOUND\n", 0,  entry.key_len,  entry.key);
	}

	return (found) ? found->id : 0;
}


/**
 * Output an integer in bytes. That is, output the number in binary, using the
 * least number of bytes possible.  All numbers are positive. Use sign slot as
 * a marker
 */
void
output_int(unsigned int i) {

	/* general case. handles all integers */
	if (i < 0x80) { /* < 8 bits */
		fputc( (char)i, out);
	}
	else if (i < 0x4000) { /* < 15 bits */
		fputc( (char)((i >> 8) | 0x80), out);
		fputc( (char)i, out);
	}
	else if (i < 0x200000) { /* < 22 bits */
		fputc( (char)((i >> 16) | 0xC0), out);
		fputc( (char)(i >> 8), out);
		fputc( (char)i, out);
	}
	else if (i < 0x10000000)  { /* 32 bits */
		fputc( (char)((i >> 24) | 0xE0), out);
		fputc( (char)(i >> 16), out);
		fputc( (char)(i >> 8), out);
		fputc( (char)i, out);
	}
	else {	/* need all the bytes. */
		fputc( 0xFF, out);
		fputc( (char)(i >> 24), out);
		fputc( (char)(i >> 16), out);
		fputc( (char)(i >> 8), out);
		fputc( (char)i, out);
	}
}

/**
 * Output a double precision float via a simple binary write of the memory.
 * (Minor portbility issues are seen as less important than speed and space.)
 */
void
output_nv(NV nv) {
	int i = sizeof(NV);
	unsigned char *p = (unsigned char *)&nv;
	while (i-- > 0) {
		fputc(*p++, out);
	}
}


static const char* block_type[] = {
    "NULL",
    "SUB",
    "EVAL",
    "LOOP",
    "SUBST",
    "BLOCK",
};


/* based on S_dopoptosub_at() from perl pp_ctl.c */
static int
dopopcx_at(pTHX_ PERL_CONTEXT *cxstk, I32 startingblock, UV stop_at)
{
    I32 i;
    register PERL_CONTEXT *cx;
    for (i = startingblock; i >= 0; i--) {
        UV type_bit;
        cx = &cxstk[i];
        type_bit = 1 << CxTYPE(cx);
        if (type_bit & stop_at)
            return i;
    }
    return i; /* == -1 */
}


static COP *
start_cop_of_context(pTHX_ PERL_CONTEXT *cx) {
    OP *start_op, *o;
    int type;
    int trace = 4;

    switch (CxTYPE(cx)) {
    case CXt_EVAL:
        start_op = (OP*)cx->blk_oldcop;
        break;
    case CXt_FORMAT:
        start_op = CvSTART(cx->blk_sub.cv);
        break;
    case CXt_SUB:
        start_op = CvSTART(cx->blk_sub.cv);
        break;
#ifdef CXt_LOOP
    case CXt_LOOP:
#  if (PERL_VERSION < 10)
        start_op = cx->blk_loop.redo_op;
#  else
        start_op = cx->blk_loop.my_op->op_redoop;
#  endif
	 break;
#else
#  if defined (CXt_LOOP_PLAIN) && defined (CXt_LOOP_FOR) && defined(CXt_LOOP_LAZYIV) && defined (CXt_LOOP_LAZYSV)
    /* This is Perl 5.11.0 or later */
    case CXt_LOOP_LAZYIV:
    case CXt_LOOP_LAZYSV:
    case CXt_LOOP_PLAIN:
    case CXt_LOOP_FOR:
	start_op = cx->blk_loop.my_op->op_redoop;
	break;
#  else
#    warning "The perl you are using is missing some essential defines.  Your results may not be accurate."
#  endif
#endif
    case CXt_BLOCK:
				/* this will be NULL for the top-level 'main' block */
        start_op = (OP*)cx->blk_oldcop;
        break;
    case CXt_SUBST:			/* FALLTHRU */
    case CXt_NULL:			/* FALLTHRU */
		default:
        start_op = NULL;
        break;
    }
    if (!start_op) {
        if (trace_level >= trace)
            warn("\tstart_cop_of_context: can't find start of %s\n", 
            			block_type[CxTYPE(cx)]);
        return NULL;
    }
    /* find next cop from OP */
		o = start_op;
    while ( o && (type = (o->op_type) ? o->op_type : o->op_targ) ) {
#ifdef OP_SETSTATE
        if (type == OP_NEXTSTATE || type == OP_SETSTATE || type == OP_DBSTATE) {
#else
        if (type == OP_NEXTSTATE || type == OP_DBSTATE) {
#endif
				  if (trace_level >= trace)
						warn("\tstart_cop_of_context %s is %s line %d of %s\n",
							block_type[CxTYPE(cx)], OP_NAME(o), (int)CopLINE((COP*)o), 
							OutCopFILE((COP*)o));
					return (COP*)o;
				}
        /* should never get here? */
        if (trace_level) {
            warn("\tstart_cop_of_context %s op '%s' isn't a cop", 
            			block_type[CxTYPE(cx)], OP_NAME(o));
				}
        if (trace_level >= 4)
            do_op_dump(1, PerlIO_stderr(), o);
        o = o->op_next;
    }
    if (trace_level >= 1) {
			warn("\tstart_cop_of_context: can't find next cop for %s line %ld\n",
					block_type[CxTYPE(cx)], (long)CopLINE(PL_curcop_nytprof));
			do_op_dump(1, PerlIO_stderr(), start_op);
		}
    return NULL;
}

static PERL_CONTEXT *
visit_contexts(pTHX_ UV stop_at, int (*callback)(pTHX_ PERL_CONTEXT *cx, 
								UV *stop_at_ptr)) 
{
    /* modelled on pp_caller() in pp_ctl.c */
    register I32 cxix = cxstack_ix;
    register PERL_CONTEXT *cx = NULL;
    register PERL_CONTEXT *ccstack = cxstack;
    PERL_SI *top_si = PL_curstackinfo;

    if (trace_level >= 4)
        warn("visit_contexts: \n");

    while (1) {
        /* we may be in a higher stacklevel, so dig down deeper */
				/* XXX so we'll miss code in sort blocks and signals?		*/
				/* callback should perhaps be moved to dopopcx_at */
        while (cxix < 0 && top_si->si_type != PERLSI_MAIN) {
            if (trace_level >= 3)
							warn("Not on main stack (type %d); digging top_si %p->%p, ccstack %p->%p\n",
										(int)top_si->si_type, top_si, top_si->si_prev, ccstack, top_si->si_cxstack);
            top_si  = top_si->si_prev;
            ccstack = top_si->si_cxstack;
            cxix = dopopcx_at(aTHX_ ccstack, top_si->si_cxix, stop_at);
        }
        if (cxix < 0 || (cxix == 0 && !top_si->si_prev)) {
						/* cxix==0 && !top_si->si_prev => top-level BLOCK */
						if (trace_level >= 4)
								warn("visit_contexts: reached top of context stack\n");
						return NULL;
        }
        cx = &ccstack[cxix];
        if (trace_level >= 4)
					warn("visit_context: %s cxix %d (si_prev %p)\n",
							block_type[CxTYPE(cx)], (int)cxix, top_si->si_prev);
				if (callback(aTHX_ cx, &stop_at))
					return cx;
        /* no joy, look further */
        cxix = dopopcx_at(aTHX_ ccstack, cxix - 1, stop_at);
    }
    return NULL; /* not reached */
}


static int
_cop_in_same_file(COP *a, COP *b)
{
  int same = 0;
  char *a_file = OutCopFILE(a);
  char *b_file = OutCopFILE(b);
	if (a_file == b_file)
		same = 1;
	else
	/* fallback to strEQ, surprisingly common (check why) XXX expensive */
  if (strEQ(a_file, b_file))
		same = 1;
  return same;
}


int
_check_context(pTHX_ PERL_CONTEXT *cx, UV *stop_at_ptr)
{
		COP *near_cop;
		PERL_UNUSED_ARG(stop_at_ptr);

		if (CxTYPE(cx) == CXt_SUB) {
				if (PL_debstash && CvSTASH(cx->blk_sub.cv) == PL_debstash)
					return 0; /* skip subs in DB package */

				near_cop = start_cop_of_context(aTHX_ cx);

				/* only use the cop if it's in the same file */
				if (_cop_in_same_file(near_cop, PL_curcop_nytprof)) {
					last_sub_line = CopLINE(near_cop);
					/* treat sub as a block if we've not found a block yet */
					if (!last_block_line)
							last_block_line = last_sub_line;
				}

				if (trace_level >= 4) {
					GV *sv = CvGV(cx->blk_sub.cv);
					warn("\tat %d: block %d sub %d for %s %s\n",
						last_executed_line, last_block_line, last_sub_line,
						block_type[CxTYPE(cx)], (sv) ? GvNAME(sv) : "");
					if (trace_level >= 9)
						sv_dump((SV*)cx->blk_sub.cv);
				}

				return 1;		/* stop looking */
		}

	/* NULL, EVAL, LOOP, SUBST, BLOCK context */
	if (trace_level >= 4)
		warn("\t%s\n", block_type[CxTYPE(cx)]);

	/* if we've got a block line, skip this context and keep looking for a sub */
	if (last_block_line)
		return 0;

	/* if we can't get a line number for this context, skip it */
	if ((near_cop = start_cop_of_context(aTHX_ cx)) == NULL)
		return 0;

	/* if this context is in a different file... */
	if (!_cop_in_same_file(near_cop, PL_curcop_nytprof)) {
		/* if we started in a string eval ... */
		if ('(' == *OutCopFILE(PL_curcop_nytprof)) {
			/* give up XXX could do better here */
			last_block_line = last_sub_line = last_executed_line;
			return 1;
		}
		/* shouldn't happen! */
		if (trace_level >= 1)
			warn("at %d: %s in different file (%s, %s)",
						last_executed_line, block_type[CxTYPE(cx)], 
						OutCopFILE(near_cop), OutCopFILE(PL_curcop_nytprof));
		return 1; /* stop looking */
	}

	last_block_line = CopLINE(near_cop);
	if (trace_level >= 4)
		warn("\tat %d: block %d for %s\n",
			last_executed_line, last_block_line, block_type[CxTYPE(cx)]);
	return 0;
}

/* copied from perl's S_closest_cop in util.c as used by warn(...) */

static const COP*
closest_cop(pTHX_ const COP *cop, const OP *o)
{
    dVAR;
    /* Look for PL_op starting from o.  cop is the last COP we've seen. */
    if (!o || o == PL_op)
        return cop;
    if (o->op_flags & OPf_KIDS) {
        const OP *kid;
        for (kid = cUNOPo->op_first; kid; kid = kid->op_sibling) {
            const COP *new_cop;
            /* If the OP_NEXTSTATE has been optimised away we can still use it
             * the get the file and line number. */
            if (kid->op_type == OP_NULL && kid->op_targ == OP_NEXTSTATE)
                cop = (const COP *)kid;
            /* Keep searching, and return when we've found something. */
            new_cop = closest_cop(aTHX_ cop, kid);
            if (new_cop)
                return new_cop;
        }
    }
    /* Nothing found. */
    return NULL;
}


/**
 * Main statement profiling function. Called before each breakable statement.
 */
void
DB_stmt(pTHX_ OP *op) {
	char *file;
	unsigned int elapsed;
	unsigned int overflow;
	COP *cop;

	if (usecputime) {
		times(&end_ctime);
		overflow = 0; /* XXX */
		elapsed = end_ctime.tms_utime - start_ctime.tms_utime
						+ end_ctime.tms_stime - start_ctime.tms_stime;
	} else {
		get_time_of_day(end_time);
		get_ticks_between(start_time, end_time, elapsed, overflow);
	}
	if (overflow)	/* XXX later output overflow to file */
		warn("profile time overflow of %d seconds discarded", overflow);

	if (!out)
		return;

	if (!is_profiling)
		return;

	if (last_executed_fid) {
		reinit_if_forked(aTHX);

		fputc( (profile_blocks) ? '*' : '+', out);
		output_int(elapsed);
		output_int(last_executed_fid);
		output_int(last_executed_line);
		if (profile_blocks) {
			output_int(last_block_line);
			output_int(last_sub_line);
		}
		if (trace_level >= 3)
			warn("Wrote %d:%-4d %2u ticks (%u, %u)\n", last_executed_fid, 
						last_executed_line, elapsed, last_block_line, last_sub_line);
	}

	cop = PL_curcop_nytprof;
	if ( (last_executed_line = CopLINE(cop)) == 0 ) {
		/* Might be a cop that has been optimised away.  We can try to find such a
		 * cop by searching through the optree starting from the sibling of PL_curcop.
		 * See Perl_vmess in perl's util.c for how warn("...") finds the line number.
		 */
		cop = closest_cop(aTHX_ cop, cop->op_sibling);
		if (!cop)
			cop = PL_curcop_nytprof;
		last_executed_line = CopLINE(cop);
		if (!last_executed_line) { /* typically when _finish called by END */
			if (op)	/* should never happen */
				warn("Unable to determine line number in %s", OutCopFILE(cop));
			last_executed_line = 1; /* don't want zero line numbers in data */
		}
	}

	file = OutCopFILE(cop);
	if (!last_executed_fid) {	/* first time */
		if (trace_level >= 1) {
			warn("NYTProf pid %ld: first statement line %d of %s",
				(long)getpid(), (int)CopLINE(cop), OutCopFILE(cop));
		}
	}
	if (file != last_executed_fileptr) {
		last_executed_fileptr = file;
		last_executed_fid = get_file_id(aTHX_ file, strlen(file), 1);
	}

	if (trace_level >= 4)
		warn("     @%d:%-4d %s", last_executed_fid, last_executed_line,
			(profile_blocks) ? "looking for block and sub lines" : "");

	if (profile_blocks) {
		last_block_line = 0;
		last_sub_line   = 0;
		if (op) {
			visit_contexts(aTHX_ ~0, &_check_context);
		}
		/* if we didn't find block or sub scopes then use current line */
		if (!last_block_line) last_block_line = last_executed_line;
		if (!last_sub_line)   last_sub_line   = last_executed_line;
	}

	if (usecputime) {
		times(&start_ctime);
	} else {
		get_time_of_day(start_time);
	}

	/* measure time we've spent measuring so we can discount it */
	get_ticks_between(end_time, start_time, elapsed, overflow);
	cumulative_overhead_ticks += elapsed;
}


static void
DB_leave(pTHX_ OP *op)
{
	int prev_last_executed_fid  = last_executed_fid;
	int prev_last_executed_line = last_executed_line;

	/* Called _after_ ops that indicate we've completed a statement
	 * and are returning into the middle of some outer statement.
	 * Used to ensure that time between now and the _next_ statement
	 * being entered, is allocated to the outer statement we've
	 * returned into and not the previous statement.
	 * PL_curcop has already been updated.
	 */

	if (!is_profiling)
		return;

	/* measure and output end time of previous statement
	 * (earlier than it would have been done)
	 * and switch back to measuring the 'calling' statement
	 */
	DB_stmt(aTHX_ op);

	/* output a 'discount' marker to indicate the next statement time shouldn't
	 * increment the count (because the time is not for a new statement but simply
	 * a continuation of a previously counted statement).
	 */
	fputc('-', out);

	if (trace_level >= 4) {
		warn("left %u:%u via %s back to %s at %u:%u (b%u s%u) - discounting next statement%s\n",
			prev_last_executed_fid, prev_last_executed_line,
			OP_NAME_safe(PL_op), OP_NAME_safe(op),
			last_executed_fid, last_executed_line, last_block_line, last_sub_line,
			(op) ? "" : ", LEAVING PERL"
		);
	}
}


/**
 * Sets or toggles the option specified by 'option'. 
 */
void
set_option(const char* option, const char* value) {

	if (strEQ(option, "file")) {
		strncpy(PROF_output_file, value, MAXPATHLEN);
	}
	else if (strEQ(option, "usecputime")) {
		usecputime = atoi(value);
	}
	else if (strEQ(option, "begin")) {
		profile_begin = atoi(value);
	}
	else if (strEQ(option, "subs")) {
		profile_subs = atoi(value);
	}
	else if (strEQ(option, "blocks")) {
		profile_blocks = atoi(value);
	}
	else if (strEQ(option, "leave")) {
		profile_leave = atoi(value);
	}
	else if (strEQ(option, "expand")) {
		embed_fid_line = atoi(value);
	}
	else if (strEQ(option, "trace")) {
		trace_level = atoi(value);
	}
	else if (strEQ(option, "use_db_sub")) {
		use_db_sub = atoi(value);
	}
	else {
		warn("Unknown option: %s\n", option);
		return;
	}
	if (trace_level)
		warn("# %s=%s\n", option, value);
}

/**
 * Open the output file. This is encapsulated because the code can be reused
 * without the environment parsing overhead after each fork.
 */
void
open_output_file(pTHX_ char *filename) {

  char filename_buf[MAXPATHLEN];

	if (out) {	/* already opened so assume forking */
		sprintf(filename_buf, "%s.%d", filename, getpid());
		filename = filename_buf;
		/* caller is expected to have purged/closed old out if appropriate */
	}

	out = fopen(filename, "wb");
	if (!out) {
		disable_profile(aTHX);
		croak("Failed to open output '%s': %s", filename, strerror(errno));
	}
	if (trace_level)
			warn("Opened %s\n", filename);

	output_header(aTHX);
}


int
reinit_if_forked(pTHX) {
	if (getpid() == last_pid)
		return 0;		/* not forked */
	/* we're now the child process */
	if (trace_level >= 1)
		warn("New pid %d (was %d)\n", getpid(), last_pid);
	/* reset state */
	last_pid = getpid();
	last_executed_fileptr = NULL;
	if (sub_callers_hv)
		hv_clear(sub_callers_hv);

#if HAS_FPURGE_BOOL
	FPURGE(out);
#else
	warn("NYTProf not built with fpurge support so %s may be corrupted by the fork", PROF_output_file);
#endif
  /* we don't bother closing the current out fh so if we don't have fpurge
	* any old pending data that was duplicated by the fork won't be written
	* until the program exits and that'll be much easier to handle by the reader
	*/
	open_output_file(aTHX_ PROF_output_file);

	return 1;		/* have forked */
}


/******************************************
 * Sub caller and inclusive time tracking
 ******************************************/

typedef struct sub_call_start_st {
  time_of_day_t sub_call_time;
	char fid_line[50];
	SV *subname_sv;
	AV *sub_av;
	NV current_overhead_ticks;
	NV current_subr_secs;
} sub_call_start_t;

void
incr_sub_inclusive_time(pTHX_ sub_call_start_t *sub_call_start) {
	AV *av = sub_call_start->sub_av;
	SV *subname_sv = sub_call_start->subname_sv;
	SV *incl_time_sv = *av_fetch(av, 1, 1);
	SV *excl_time_sv = *av_fetch(av, 2, 1);
	/* statement overheads we've accumulated since we entered the sub */
	int overhead_ticks = (cumulative_overhead_ticks - sub_call_start->current_overhead_ticks);
	/* seconds spent in subroutines called by this subroutine */
	NV called_sub_secs = (cumulative_subr_secs      - sub_call_start->current_subr_secs);
	NV incl_subr_sec;
	NV excl_subr_sec;

	if (profile_zero) {
		incl_subr_sec = 0.0;
		excl_subr_sec = 0.0;
	}
	else {
		time_of_day_t sub_end_time;
		unsigned int ticks, overflow;
		/* calculate ticks since we entered the sub */
		get_time_of_day(sub_end_time);
		get_ticks_between(sub_call_start->sub_call_time, sub_end_time, ticks, overflow);
		ticks -= overhead_ticks; /* subtract statement measurement overheads */
		incl_subr_sec = overflow + ticks / (NV)ticks_per_sec;
		excl_subr_sec = incl_subr_sec - called_sub_secs;
	}

	if (trace_level >= 3)
		warn("exited %s after %"NVff"s incl - %"NVff"s = %"NVff"s excl (%"NVff"s @ %s, oh %g-%g=%dt)\n",
			SvPV_nolen(subname_sv), incl_subr_sec, called_sub_secs, excl_subr_sec,
			SvNV(incl_time_sv)+incl_subr_sec, sub_call_start->fid_line,
			cumulative_overhead_ticks, sub_call_start->current_overhead_ticks, overhead_ticks);

	sv_setnv(incl_time_sv, SvNV(incl_time_sv)+incl_subr_sec);
	sv_setnv(excl_time_sv, SvNV(excl_time_sv)+excl_subr_sec);
	sv_free(sub_call_start->subname_sv);

	cumulative_subr_secs += excl_subr_sec;
}

void	/* wrapper called via scope exit due to save_destructor below */
incr_sub_inclusive_time_ix(pTHX_ void *save_ix_void) {
	I32 save_ix = (I32)save_ix_void;
	sub_call_start_t *sub_call_start = SSPTR(save_ix, sub_call_start_t *);
  incr_sub_inclusive_time(aTHX_ sub_call_start);
}


OP *
pp_entersub_profiler(pTHX) {
	OP *op;
	COP *prev_cop = PL_curcop; /* not PL_curcop_nytprof here */
	OP *next_op = PL_op->op_next; /* op to execute after sub returns */
	dSP;
	SV *sub_sv = *SP;
  sub_call_start_t sub_call_start;

	if (profile_subs && is_profiling) {
		get_time_of_day(sub_call_start.sub_call_time);
		sub_call_start.current_overhead_ticks = cumulative_overhead_ticks;
		sub_call_start.current_subr_secs = cumulative_subr_secs;
	}

	/*
	 * for normal subs pp_entersub enters the sub
	 * and returns the first op *within* the sub (typically a dbstate).
	 * for XS subs pp_entersub executes the entire sub
	 * and returning the op *after* the sub (PL_op->op_next)
	 */
	op = run_original_op(OP_ENTERSUB);

	if (is_profiling) {

		/* get line, file, and fid for statement *before* the call */

		char *file = OutCopFILE(prev_cop);
		unsigned int fid = (file == last_executed_fileptr)
			? last_executed_fid
			: get_file_id(aTHX_ file, strlen(file), 1);
		/* XXX could use same closest_cop as DB_stmt() but it doesn't seem
		 * to be needed here. Line is 0 only when call is from embedded
		 * C code like mod_perl (at least in my testing so far)
		 */
		int line = CopLINE(prev_cop);
		char fid_line_key[50];
		int fid_line_key_len = my_snprintf(fid_line_key, sizeof(fid_line_key), "%u:%d", fid, line);
		SV *subname_sv = newSV(0);
		SV *sv_tmp;
		CV *cv;
		int is_xs;

		if (op != next_op) { /* have entered a sub */
			/* use cv of sub we've just entered to get name */
			sub_sv = (SV *)cxstack[cxstack_ix].blk_sub.cv;
			is_xs = 0;
		}
		else { /* have returned from XS so use sub_sv for name */
			is_xs = 1;
		}

		/* determine the original fully qualified name for sub */
		/* XXX hacky with lots of obscure edge cases */
		/* basically needs to be clone of first part of pp_entersub, but isn't */
		if (SvROK(sub_sv))
			sub_sv = SvRV(sub_sv);
		cv = (isGV(sub_sv)) ? GvCV(sub_sv) : (SvTYPE(sub_sv) == SVt_PVCV) ? (CV *)sub_sv : NULL;
		if (cv && CvGV(cv) && GvSTASH(CvGV(cv))) {
			/* for a plain call of an imported sub the GV is of the current
				* package, so we dig to find the original package
				*/
			GV *gv = CvGV(cv);
			sv_setpvf(subname_sv, "%s::%s", HvNAME(GvSTASH(gv)), GvNAME(gv));
		}
		else if (isGV(sub_sv)) {
			gv_efullname3(subname_sv, (GV *)sub_sv, Nullch);
		}
		else if (SvTYPE(sub_sv) == SVt_PVCV) {
			/* unnamed CV, e.g. seen in mod_perl. XXX do better? */
			sv_setpvn(subname_sv, "__ANON__", 8);
		}
		else if (SvTYPE(sub_sv) == SVt_PV
				/* Errno.pm does &$errname and sub_sv is PVIV! with POK */
			|| SvPOK(sub_sv)
		) {
			sv_setsv(subname_sv, sub_sv);
		}
		else {
			const char *what = (is_xs) ? "xs" : "sub";
			warn("unknown entersub %s '%s'", what, SvPV_nolen(sub_sv));
			if (trace_level || 1)
				sv_dump(sub_sv);
			sv_setpvf(subname_sv, "(unknown %s %s)", what, SvPV_nolen(sub_sv));
		}

		if (trace_level >= 3)
			fprintf(stderr, "fid %d:%d called %s %s (oh %gt, sub %gs)\n", fid, line, 
				SvPV_nolen(subname_sv), (is_xs) ? "xs" : "sub",
				sub_call_start.current_overhead_ticks,
				sub_call_start.current_subr_secs);

		/* { subname => { "fid:line" => [ count, incl_time ] } } */
		sv_tmp = *hv_fetch(sub_callers_hv, SvPV_nolen(subname_sv), 
												SvCUR(subname_sv), 1);
		if (!SvROK(sv_tmp)) { /* autoviv hash ref */
			HV *hv = newHV();
			sv_setsv(sv_tmp, newRV_noinc((SV *)hv));
			/* create dummy item to hold flag to indicate xs */
			if (is_xs) {
				AV *av = newAV();
				av_store(av, 0, newSVuv(1));    /* flag to indicate xs */
				av_store(av, 1, newSVnv(0.0));
				av_store(av, 2, newSVnv(0.0));
				av_store(av, 3, newSVnv(0.0));
				av_store(av, 4, newSVnv(0.0));
				sv_setsv(*hv_fetch(hv, "0:0", 3, 1), newRV_noinc((SV *)av));
			}
		}

		sv_tmp = *hv_fetch((HV*)SvRV(sv_tmp), fid_line_key, fid_line_key_len, 1);
		if (!SvROK(sv_tmp)) { /* autoviv array ref */
			AV *av = newAV();
			av_store(av, 0, newSVuv(1));    /* count of call to sub */
			av_store(av, 1, newSVnv(0.0));	/* inclusive time in sub */
			av_store(av, 2, newSVnv(0.0));	/* exclusive time in sub */
			av_store(av, 3, newSVnv(0.0));	/* incl user cpu time in sub */
			av_store(av, 4, newSVnv(0.0));	/* incl sys  cpu time in sub */
			sv_setsv(sv_tmp, newRV_noinc((SV *)av));
		}
		else {
			sv_inc(AvARRAY(SvRV(sv_tmp))[0]);
		}

		if (profile_subs) {
			sub_call_start.subname_sv = subname_sv;
			sub_call_start.sub_av = (AV *)SvRV(sv_tmp);
			strcpy(sub_call_start.fid_line, fid_line_key);
			if (is_xs) {
				/* acculumate now time we've just spent in the xs sub */
				incr_sub_inclusive_time(aTHX_ &sub_call_start);
			}
			else {
				/* copy struct to save stack (very efficient) */
				I32 save_ix = SSNEWa(sizeof(sub_call_start), MEM_ALIGNBYTES);
				Copy(&sub_call_start, SSPTR(save_ix, sub_call_start_t *), 1, sub_call_start_t);
				/* defer acculumating time spent until we leave the sub */
				save_destructor_x(incr_sub_inclusive_time_ix, (void *)save_ix);
			}
		}
		else {
			sv_free(subname_sv);
		}
	}

	return op;
}


OP *
pp_stmt_profiler(pTHX) {    /* handles OP_DBSTATE, OP_SETSTATE, etc */
	OP *op = run_original_op(PL_op->op_type);
	DB_stmt(aTHX_ op);
	return op;
}
OP *
pp_leaving_profiler(pTHX) { /* handles OP_LEAVESUB, OP_LEAVEEVAL, etc */
	OP *op = run_original_op(PL_op->op_type);
	DB_leave(aTHX_ op);
	return op;
}
OP *
pp_exit_profiler(pTHX) {   	/* handles OP_EXIT, OP_EXEC, etc */
	DB_leave(aTHX_ NULL);     /* call DB_leave *before* run_original_op() */
	if (PL_op->op_type == OP_EXEC)
		finish_profile(aTHX);   /* this is the last chance we'll get */
	return run_original_op(PL_op->op_type);
}


/************************************
 * Shared Reader,NYTProf Functions  *
 ************************************/

static int
enable_profile(pTHX)
{
	int prev_is_profiling = is_profiling;
	if (trace_level)
		warn("NYTProf enable_profile%s", (prev_is_profiling)?" (already enabled)":"");
	is_profiling = 1;
	last_executed_fileptr = NULL;
	if (use_db_sub)
		sv_setiv(PL_DBsingle, 1);
	return prev_is_profiling;
}

static int
disable_profile(pTHX)
{
	int prev_is_profiling = is_profiling;
	sv_setiv(PL_DBsingle, 0);
	is_profiling = 0;
	if (out)
		fflush(out);
	if (trace_level)
		warn("NYTProf disable_profile");
	return prev_is_profiling;
}

static void
finish_profile(pTHX)
{
	if (trace_level)
		warn("finish_profile (last_pid %d, getpid %d, overhead %"NVff"s)\n",
			last_pid, getpid(), cumulative_overhead_ticks/ticks_per_sec);

	/* write data for final statement, unless DB_leave has already */
	if (!profile_leave || use_db_sub)
		DB_stmt(aTHX_ NULL);

	disable_profile(aTHX);

	if (out) {
		write_sub_line_ranges(aTHX_ 0);
		write_sub_callers(aTHX);
		/* mark end of profile data for last_pid pid
		 * (which is the pid that relates to the out filehandle)
		 */
		END_OUTPUT_PID(last_pid);
		if (-1 == fclose(out))
			warn("Error closing profile data file: %s", strerror(errno));
		out = NULL;
	}
}


/* Initial setup */
int
init_profiler(pTHX) {
	unsigned int hashtable_memwidth;
#ifndef HAS_GETTIMEOFDAY
	SV **svp;
#endif

	/* Save the process id early. We monitor it to detect forks */
	last_pid = getpid();
	ticks_per_sec = (usecputime) ? CLOCKS_PER_SEC : CLOCKS_PER_TICK;

	if (trace_level || profile_zero)
		warn("NYTProf init pid %d%s\n", last_pid, profile_zero ? ", zero=1" : "");

	if (get_hv("DB::sub", 0) == NULL) {
		warn("NYTProf internal error - perl not in debug mode");
		return 0;
	}

#ifndef HAS_GETTIMEOFDAY
	require_pv("Time/HiRes.pm"); /* before opcode redirection */
	svp = hv_fetch(PL_modglobal, "Time::U2time", 12, 0);
	if (!svp || !SvIOK(*svp)) croak("Time::HiRes is required");
	u2time = INT2PTR(int(*)(pTHX_ UV*), SvIV(*svp));
	if (trace_level)
		warn("Using Time::HiRes %p\n", u2time);
#endif

	/* create file id mapping hash */
	hashtable_memwidth = sizeof(Hash_entry*) * hashtable.size;
	hashtable.table = (Hash_entry**)safemalloc(hashtable_memwidth);
	memset(hashtable.table, 0, hashtable_memwidth);
	
	open_output_file(aTHX_ PROF_output_file);

	/* redirect opcodes for statement profiling */
	New(0, PL_ppaddr_orig, OP_max, void *);
	Copy(PL_ppaddr, PL_ppaddr_orig, OP_max, void *);
	if (!use_db_sub) {
		PL_ppaddr[OP_NEXTSTATE]  = pp_stmt_profiler;
		PL_ppaddr[OP_DBSTATE]    = pp_stmt_profiler;
#ifdef OP_SETSTATE
		PL_ppaddr[OP_SETSTATE]   = pp_stmt_profiler;
#endif
		if (profile_leave) {
			PL_ppaddr[OP_LEAVESUB]   = pp_leaving_profiler;
			PL_ppaddr[OP_LEAVESUBLV] = pp_leaving_profiler;
			PL_ppaddr[OP_LEAVE]      = pp_leaving_profiler;
			PL_ppaddr[OP_LEAVELOOP]  = pp_leaving_profiler;
			PL_ppaddr[OP_LEAVEWRITE] = pp_leaving_profiler;
			PL_ppaddr[OP_LEAVEEVAL]  = pp_leaving_profiler;
			PL_ppaddr[OP_LEAVETRY]   = pp_leaving_profiler;
			PL_ppaddr[OP_DUMP]       = pp_leaving_profiler;
			PL_ppaddr[OP_RETURN]     = pp_leaving_profiler;
			PL_ppaddr[OP_UNSTACK]    = pp_leaving_profiler; /* natural end of simple loop */
			/* OP_NEXT is missing because that jumps to OP_UNSTACK */
			/* OP_EXIT and OP_EXEC need special handling */
			PL_ppaddr[OP_EXIT]       = pp_exit_profiler;
			PL_ppaddr[OP_EXEC]       = pp_exit_profiler;
		}
	}

	/* redirect opcodes for caller tracking */
	if (!sub_callers_hv)
		sub_callers_hv = newHV();
	PL_ppaddr[OP_ENTERSUB] = pp_entersub_profiler;

	if (profile_begin) {
		enable_profile(aTHX);
	}
	else {
		SV *enable_profile_sv = (SV *)get_cv("DB::enable_profile", GV_ADDWARN);
		if (trace_level >= 2)
			warn("enable_profile defered to INIT phase");
		/* INIT { enable_profile() } */
		if (!PL_initav)
			PL_initav = newAV();
		av_unshift(PL_initav, 1); /* we want to be first */
		av_store(PL_initav, 0, SvREFCNT_inc(enable_profile_sv));
	}

	/* END { _finish() } */
	if (!PL_endav)
		PL_endav = newAV();
	av_push(PL_endav, (SV *)get_cv("DB::_finish", GV_ADDWARN));

	/* seed first run time */
	if (usecputime) {
		times(&start_ctime);
	} else {
		get_time_of_day(start_time);
	}
  return 1;
}

/************************************
 * Devel::NYTProf::Reader Functions *
 ************************************/

void
add_entry(pTHX_ AV *dest_av, unsigned int file_num, unsigned int line_num,			
					NV time, unsigned int eval_file_num, unsigned int eval_line_num, int count) 
{
  /* get ref to array of per-line data */
  unsigned int fid = (eval_line_num) ? eval_file_num : file_num;
	SV *line_time_rvav = *av_fetch(dest_av, fid, 1);

	if (!SvROK(line_time_rvav))		/* autoviv */
			sv_setsv(line_time_rvav, newRV_noinc((SV*)newAV()));

  if (!eval_line_num) {
		store_profile_line_entry(aTHX_ line_time_rvav, line_num, time, count, fid);
	}
	else {
		/* times for statements executed *within* a string eval are accumulated
		 * embedded nested within the line the eval is on but without increasing
		 * the time or count of the eval itself. Instead the time and count is
		 * accumulated for each line within the eval on an embedded array reference.
		 */
		AV *av = store_profile_line_entry(aTHX_ line_time_rvav, eval_line_num, 0, 0, fid);

		SV *eval_line_time_rvav = *av_fetch(av, 2, 1);
		if (!SvROK(eval_line_time_rvav))		/* autoviv */
				sv_setsv(eval_line_time_rvav, newRV_noinc((SV*)newAV()));

		store_profile_line_entry(aTHX_ eval_line_time_rvav, line_num, time, count, fid);
	}
}


AV *
store_profile_line_entry(pTHX_ SV *rvav, unsigned int line_num, NV time, 
													int count, unsigned int fid)
{
	SV *time_rvav = *av_fetch((AV*)SvRV(rvav), line_num, 1);
	AV *line_av;
	if (!SvROK(time_rvav)) {		  /* autoviv */
		line_av = newAV();
		sv_setsv(time_rvav, newRV_noinc((SV*)line_av));
		av_store(line_av, 0, newSVnv(time));
		av_store(line_av, 1, newSViv(count));
		/* if eval then   2  is used for lines within the string eval */
		if (embed_fid_line) {	/* used to optimize reporting */
			av_store(line_av, 3, newSVuv(fid));
			av_store(line_av, 4, newSVuv(line_num));
		}
	}
	else {
		SV *time_sv;
		line_av = (AV*)SvRV(time_rvav);
		time_sv = *av_fetch(line_av, 0, 1);
		sv_setnv(time_sv, time + SvNV(time_sv));
		if (count) {
		  SV *sv = *av_fetch(line_av, 1, 1);
			(count == 1) ? sv_inc(sv) : sv_setiv(sv, time + SvIV(sv));
		}
	}
	return line_av;
}


void
write_sub_line_ranges(pTHX_ int fids_only) {
	char *sub_name;
	I32 sub_name_len;
	SV *file_lines_sv;
	HV *hv = GvHV(PL_DBsub);

	if (trace_level >= 2)
		warn("writing sub line ranges\n");

	hv_iterinit(hv);
	while (NULL != (file_lines_sv = hv_iternextsv(hv, &sub_name, &sub_name_len))) 
	{
		char *file_lines = SvPV_nolen(file_lines_sv); /* "filename:first-last" */
		char *first = strrchr(file_lines, ':');
		char *last = (first) ? strchr(first, '-') : NULL;
		unsigned int fid;
		UV first_line, last_line;

		if (!first || !last || !grok_number(first+1, last-first-1, &first_line)) {
			warn("Can't parse %%DB::sub entry for %s '%s'\n", sub_name, file_lines);
			continue;
		} 
		last_line = atoi(++last);

		if (!first_line && !last_line && strstr(sub_name, "::BEGIN"))
			continue;	/* no point writing these */

		fid = get_file_id(aTHX_ file_lines, first - file_lines, 0);
		if (!fid)  /* no point in writing subs in files we've not profiled */
			continue;
		if (fids_only)  /* caller just wants fids assigned */
			continue;

		if (trace_level >= 2)
			warn("Sub %s fid %u lines %lu..%lu\n",
				sub_name, fid, (unsigned long)first_line, (unsigned long)last_line);

		fputc('s', out);
		output_int(fid);
		output_int(first_line);
		output_int(last_line);
		fputs(sub_name, out);
		fputc('\n', out);
	}
}


void
write_sub_callers(pTHX) {
	char *sub_name;
	I32 sub_name_len;
	SV *fid_line_rvhv;

	if (!sub_callers_hv)
		return;
	if (trace_level >= 2)
		warn("writing sub callers\n");

	hv_iterinit(sub_callers_hv);
	while (NULL != (fid_line_rvhv = hv_iternextsv(sub_callers_hv, &sub_name, 
									&sub_name_len))) 
	{
		HV *fid_lines_hv = (HV*)SvRV(fid_line_rvhv);
		char *fid_line_string;
		I32 fid_line_len;
		SV *sv;

		hv_iterinit(fid_lines_hv);
		while (NULL != (sv = hv_iternextsv(fid_lines_hv, &fid_line_string,
										&fid_line_len))) 
		{
			AV *av = (AV *)SvRV(sv);
			unsigned int count = SvUV(AvARRAY(av)[0]);
			unsigned int fid = 0;
			unsigned int line = 0;
			sscanf(fid_line_string, "%u:%u", &fid, &line);
			if (trace_level >= 3)
				warn("%s called by %u:%u: count %d (%"NVff"s %"NVff"s %"NVff"s %"NVff"s)\n",
					sub_name, fid, line, count,
					SvNV(AvARRAY(av)[1]), SvNV(AvARRAY(av)[2]),
					SvNV(AvARRAY(av)[3]), SvNV(AvARRAY(av)[4]) );

			fputc('c', out);
			output_int(fid);
			output_int(line);
			output_int(count);
			output_nv( SvNV(AvARRAY(av)[1]) );
			output_nv( SvNV(AvARRAY(av)[2]) );
			output_nv( SvNV(AvARRAY(av)[3]) );
			output_nv( SvNV(AvARRAY(av)[4]) );
			fputs(sub_name, out);
			fputc('\n', out);
		}
	}
}


/**
 * Read an integer by decompressing the next 1 to 4 bytes of binary into a 32-
 * bit integer. See output_int() for the compression details.
 */
unsigned int
read_int() {

	static unsigned char d;
	static unsigned int newint;

	d = fgetc(in);
	if (d < 0x80) { /* 7 bits */
		newint = d;
	}
	else if (d < 0xC0) { /* 14 bits */
		newint = d & 0x7F;
		newint <<= 8;
		newint |= (unsigned char)fgetc(in);
	} 
	else if (d < 0xE0) { /* 21 bits */
		newint = d & 0x1F;
		newint <<= 8;
		newint |= (unsigned char)fgetc(in);
		newint <<= 8;
		newint |= (unsigned char)fgetc(in);
	} 
	else if (d < 0xFF) { /* 28 bits */
		newint = d & 0xF;
		newint <<= 8;
		newint |= (unsigned char)fgetc(in);
		newint <<= 8;
		newint |= (unsigned char)fgetc(in);
		newint <<= 8;
		newint |= (unsigned char)fgetc(in);
	} 
	else if (d == 0xFF) { /* 32 bits */
		newint = (unsigned char)fgetc(in);
		newint <<= 8;
		newint |= (unsigned char)fgetc(in);
		newint <<= 8;
		newint |= (unsigned char)fgetc(in);
		newint <<= 8;
		newint |= (unsigned char)fgetc(in);
	}
	return newint;
}

/**
 * Read an NV by simple byte copy to memory
 * bit integer. See output_int() for the compression details.
 */
NV
read_nv() {
	NV nv;
	int i = sizeof(NV);
	unsigned char *p = (unsigned char *)&nv;
	while (i-- > 0) {
		*p++ = (unsigned char)fgetc(in);
	}
	return nv;
}


AV *
lookup_subinfo_av(pTHX_ char *subname, STRLEN len, HV *sub_subinfo_hv)
{
	SV *sv;
	if (!len)
		len = strlen(subname);
	/* { 'pkg::sub' => [
		*			fid, first_line, last_line, incl_time
		*		], ... }
		*/
	sv = *hv_fetch(sub_subinfo_hv, subname, len, 1);
	if (!SvROK(sv))	{	/* autoviv */
		AV *av = newAV();
		SV *rv = newRV_noinc((SV *)av);
		/* 0: fid - may be undef
		 * 1: start_line - may be undef if not known and not known to be xs
		 * 2: end_line - ditto
		 */
		sv_setuv(*av_fetch(av, 3, 1), 0);	/* call count */
		sv_setnv(*av_fetch(av, 4, 1), 0);	/* incl_time */
		sv_setnv(*av_fetch(av, 5, 1), 0);	/* excl_time */
		sv_setsv(sv, rv);
  }
	return (AV *)SvRV(sv);
}


/**
 * Process a profile output file and return the results in a hash like
 * { fid_fileinfo  => [ [file, other...info ], ... ], # index by [fid]
 *   fid_line_time  => [ [...],[...],..  ] # index by [fid][line]
 * }
 * The value of each [fid][line] is an array ref containing:
 * [ number of calls, total time spent ]
 * lines containing string evals also get an extra element
 * [ number of calls, total time spent, [...] ]
 * which is an reference to an array containing the [calls,time]
 * data for each line of the string eval.
 */
HV*
load_profile_data_from_stream() {
	dTHX; 
	int file_major, file_minor;

	unsigned long input_line = 0L;
	unsigned int file_num = 0;
	unsigned int line_num = 0;
	unsigned int ticks;
	char text[MAXPATHLEN*2];
	int c; /* for while loop */
	int statement_discount = 0;
	NV total_stmt_seconds = 0.0;
	int total_stmt_measures = 0;
	int total_stmt_discounts = 0;
	HV *profile_hv;
	HV* profile_modes = newHV();
	HV *live_pids_hv = newHV();
	HV *attr_hv = newHV();
	AV* fid_fileinfo_av = newAV();
	AV* fid_line_time_av = newAV();
	AV* fid_block_time_av = NULL;
	AV* fid_sub_time_av = NULL;
	HV* sub_subinfo_hv = newHV();
	HV* sub_callers_hv = newHV();

	av_extend(fid_fileinfo_av, 64);  /* grow it up front. */
	av_extend(fid_line_time_av, 64);

	if (2 != fscanf(in, "NYTProf %d %d\n", &file_major, &file_minor)) {
		croak("Profile format error while parsing header");
	}
	if (file_major != 1)
		croak("Profile format version %d.%d not supported", file_major, file_minor);

	while (EOF != (c = fgetc(in))) {
		input_line++;
		if (trace_level >= 6)
			warn("Token %lu is %d ('%c') at %ld\n", input_line, c, c, (long)ftell(in)-1);

		switch (c) {
			case '-':
			{
				if (statement_discount)
					warn("multiple statement discount after %u:%d\n", file_num, line_num);
				++statement_discount;
				++total_stmt_discounts;
				break;
			}

			case '*':			/*FALLTHRU*/
			case '+':
			{
				SV *filename_sv;
				NV seconds;
				unsigned int eval_file_num = 0;
				unsigned int eval_line_num = 0;

				ticks    = read_int();
				seconds  = (NV)ticks / ticks_per_sec;
				total_stmt_seconds += seconds;
				file_num = read_int();
				line_num = read_int();

				filename_sv = *av_fetch(fid_fileinfo_av, file_num, 1);
				if (!SvROK(filename_sv)) {
					if (!SvOK(filename_sv)) { /* only warn once */
						warn("Fid %u used but not defined", file_num);
						sv_setsv(filename_sv, &PL_sv_no);
					}
				}
				else {
					AV *fid_av = (AV *)SvRV(filename_sv);
					eval_file_num = SvUV(*av_fetch(fid_av,1,1));
					eval_line_num = SvUV(*av_fetch(fid_av,2,1));
					if (eval_file_num) /* fid is an eval */
						file_num = eval_file_num;
				}

				add_entry(aTHX_ fid_line_time_av, file_num, line_num,
						seconds, eval_file_num, eval_line_num,
						1-statement_discount
				);
				if (trace_level >= 3)
						warn("Read %d:%-4d %2u ticks\n", file_num, line_num, ticks);

				if (c == '*') {
					unsigned int block_line_num = read_int();
					unsigned int sub_line_num   = read_int();

					if (!fid_block_time_av)
						fid_block_time_av = newAV();
					add_entry(aTHX_ fid_block_time_av, file_num, block_line_num,
							seconds, eval_file_num, eval_line_num,
							1-statement_discount
					);

					if (!fid_sub_time_av)
						fid_sub_time_av = newAV();
					add_entry(aTHX_ fid_sub_time_av, file_num, sub_line_num,
							seconds, eval_file_num, eval_line_num,
							1-statement_discount
					);

					if (trace_level >= 3)
							warn("\tblock %u, sub %u\n", block_line_num, sub_line_num);
				}

				total_stmt_measures++;
				statement_discount = 0;
				break;
			}

			case '@':	/* file */
			{
				AV *av;
				unsigned int eval_file_num;
				unsigned int eval_line_num;
				unsigned int fid_flags = 0;
				unsigned int file_size = 0;
				unsigned int file_mtime = 0;

				file_num  = read_int();
				eval_file_num = read_int();
				eval_line_num = read_int();
				if (file_major > 1 || (file_major == 1 && file_minor >= 1)) {
					fid_flags     = read_int();
					file_size     = read_int();
					file_mtime    = read_int();
				}

				if (NULL == fgets(text, sizeof(text), in))
					/* probably EOF */
					croak("Profile format error while reading fid declaration"); 
				if (trace_level) {
						if (eval_file_num)
							warn("Fid %2u is %.*s (eval fid %u line %u)\n",
									file_num, (int)strlen(text)-1, text, eval_file_num, eval_line_num);
						else
							warn("Fid %2u is %.*s\n",
									file_num, (int)strlen(text)-1, text);
				}

				if (av_exists(fid_fileinfo_av, file_num)) {
						/* should never happen, perhaps file is corrupt */
						AV *old_av = (AV *)SvRV(*av_fetch(fid_fileinfo_av, file_num, 1));
						SV *old_name = *av_fetch(old_av, 0, 1);
						warn("Fid %d redefined from %s to %s", file_num,
									SvPV_nolen(old_name), text);
				}

				/* [ name, eval_file_num, eval_line_num, fid, flags, size, mtime, ... ] 
					*/
				av = newAV();
				av_store(av, 0, newSVpvn(text, strlen(text)-1)); /* drop newline */
				av_store(av, 1, (eval_file_num) ? newSVuv(eval_file_num) : &PL_sv_no);
				av_store(av, 2, (eval_file_num) ? newSVuv(eval_line_num) : &PL_sv_no);
				av_store(av, 3, newSVuv(file_num));
				av_store(av, 4, newSVuv(fid_flags));
				av_store(av, 5, newSVuv(file_size));
				av_store(av, 6, newSVuv(file_mtime));
				/* 7: profile ref */

				av_store(fid_fileinfo_av, file_num, newRV_noinc((SV*)av));
				break;
			}

			case 's':	/* subroutine file line range */
			{
				AV *av;
				unsigned int fid        = read_int();
				unsigned int first_line = read_int();
				unsigned int last_line  = read_int();
				if (NULL == fgets(text, sizeof(text), in))
					croak("Profile format error in sub line range"); /* probably EOF */
				if (trace_level >= 3)
				    warn("Sub %.*s fid %u lines %u..%u\n",
							(int)strlen(text)-1, text, fid, first_line, last_line);
				av = lookup_subinfo_av(aTHX_ text, strlen(text)-1, sub_subinfo_hv);
				sv_setuv(*av_fetch(av, 0, 1), fid);
				sv_setuv(*av_fetch(av, 1, 1), first_line);
				sv_setuv(*av_fetch(av, 2, 1), last_line);
				/* [3] used for call count - updated by sub caller info below */
				/* [4] used for incl_time - updated by sub caller info below */
				break;
			}

			case 'c':	/* sub callers */
			{
				SV *sv;
				AV *subinfo_av;
				int len;
				unsigned int fid   = read_int();
				unsigned int line  = read_int();
				unsigned int count = read_int();
				NV incl_time       = read_nv();
				NV excl_time       = 0.0;
				NV ucpu_time       = 0.0;
				NV scpu_time       = 0.0;
				if (file_major > 1 || (file_major == 1 && file_minor >= 2)) {
					excl_time        = read_nv();
					ucpu_time        = read_nv();
					scpu_time        = read_nv();
				}
				if (NULL == fgets(text, sizeof(text), in))
					croak("Profile format error in sub line range"); /* probably EOF */

				if (trace_level >= 3)
				    warn("Sub %.*s called by fid %u line %u: count %d\n",
							(int)strlen(text)-1, text, fid, line, count);

				subinfo_av = lookup_subinfo_av(aTHX_ text, strlen(text)-1, sub_subinfo_hv);

				/* { 'pkg::sub' => { fid => { line => [ count, incl_time, excl_time ] } } } */
				sv = *hv_fetch(sub_callers_hv, text, strlen(text)-1, 1);
				if (!SvROK(sv))		/* autoviv */
						sv_setsv(sv, newRV_noinc((SV*)newHV()));

				len = my_snprintf(text, sizeof(text), "%u", fid);
				sv = *hv_fetch((HV*)SvRV(sv), text, len, 1);
				if (!SvROK(sv)) /* autoviv */
					sv_setsv(sv, newRV_noinc((SV*)newHV()));

				if (fid) {
					len = my_snprintf(text, sizeof(text), "%u", line);
					sv = *hv_fetch((HV*)SvRV(sv), text, len, 1);
					if (!SvROK(sv)) /* autoviv */
						sv_setsv(sv, newRV_noinc((SV*)newAV()));
					sv = SvRV(sv);
					sv_setuv(*av_fetch((AV *)sv, 0, 1), count);
					sv_setnv(*av_fetch((AV *)sv, 1, 1), incl_time);
					sv_setnv(*av_fetch((AV *)sv, 2, 1), excl_time);
					sv_setnv(*av_fetch((AV *)sv, 3, 1), ucpu_time);
					sv_setnv(*av_fetch((AV *)sv, 4, 1), scpu_time);
				}
				else { /* is meta-data about sub */
					/* line == 0: is_xs - set line range to 0,0 as marker */
					sv_setiv(*av_fetch(subinfo_av, 1, 1), 0);
					sv_setiv(*av_fetch(subinfo_av, 2, 1), 0);
				}

				/* accumulate per-sub totals into subinfo */
				sv = *av_fetch(subinfo_av, 3, 1);	/* sub call count */
				sv_setuv(sv, count     + (SvOK(sv) ? SvUV(sv) : 0));
				sv = *av_fetch(subinfo_av, 4, 1); /* sub incl_time */
				sv_setnv(sv, incl_time + (SvOK(sv) ? SvNV(sv) : 0.0));
				sv = *av_fetch(subinfo_av, 5, 1); /* sub excl_time */
				sv_setnv(sv, excl_time + (SvOK(sv) ? SvNV(sv) : 0.0));

				break;
			}

			case 'P':
			{
				unsigned int pid  = read_int();
				unsigned int ppid = read_int();
				int len = my_snprintf(text, sizeof(text), "%d", pid);
				hv_store(live_pids_hv, text, len, newSVuv(ppid), 0);
				if (trace_level)
					warn("Start of profile data for pid %s (ppid %d, %"IVdf" pids live)\n",
						text, ppid, HvKEYS(live_pids_hv));
				break;
			}

			case 'p':
			{
				unsigned int pid = read_int();
				int len = my_snprintf(text, sizeof(text), "%d", pid);
				if (!hv_delete(live_pids_hv, text, len, 0))
					warn("Inconsistent pids in profile data (pid %d not introduced)", 
								pid);
				if (trace_level)
					warn("End of profile data for pid %s, %"IVdf" remaining\n", text, 
								HvKEYS(live_pids_hv));
				break;
			}

			case ':':	/* attribute (as text) */
			{
				char *value, *end;
				SV *value_sv;
				if (NULL == fgets(text, sizeof(text), in))
					croak("Profile format error reading attribute"); /* probably EOF */
				if ((NULL == (value = strchr(text, '=')))
				||  (NULL == (end   = strchr(text, '\n')))
				) {
					warn("attribute malformed '%s'\n", text);
					continue;
				}
				*value++ = '\0';
				value_sv = newSVpvn(value, end-value);
				hv_store(attr_hv, text, strlen(text), value_sv, 0);
				if (trace_level >= 2)
				    warn(": %s = '%s'\n", text, SvPV_nolen(value_sv)); /* includes \n */
				if ('t' == *text && strEQ(text, "ticks_per_sec"))
					ticks_per_sec = SvUV(value_sv);
				break;
			}

			case '#':
				if (NULL == fgets(text, sizeof(text), in))
					croak("Profile format error reading comment"); /* probably EOF */
				if (trace_level >= 2)
				    warn("# %s", text); /* includes \n */
				break;

			default:
				croak("File format error: token %d ('%c'), line %lu", c, c, input_line);
		}
	}

	if (EOF == c && HvKEYS(live_pids_hv)) {
		warn("profile data possibly truncated, no terminator for %"IVdf" pids", 
					HvKEYS(live_pids_hv));
	}
	sv_free((SV*)live_pids_hv);

	if (trace_level >= 1)
			warn("Statement totals: measured %d, discounted %d, time %"NVff"s\n",
				total_stmt_measures, total_stmt_discounts, total_stmt_seconds);

	profile_hv = newHV();
	hv_stores(profile_hv, "attribute",      	newRV_noinc((SV*)attr_hv));
	hv_stores(profile_hv, "fid_fileinfo",   	newRV_noinc((SV*)fid_fileinfo_av));
	hv_stores(profile_hv, "fid_line_time",  	newRV_noinc((SV*)fid_line_time_av)); 
	hv_stores(profile_modes, "fid_line_time", newSVpvf("line"));
	if (fid_block_time_av) {
		hv_stores(profile_hv, "fid_block_time", 	 newRV_noinc((SV*)fid_block_time_av)); 
		hv_stores(profile_modes, "fid_block_time", newSVpvf("block"));
	}
	if (fid_sub_time_av) {
		hv_stores(profile_hv, "fid_sub_time",    newRV_noinc((SV*)fid_sub_time_av)); 
		hv_stores(profile_modes, "fid_sub_time", newSVpvf("sub"));
	}
	hv_stores(profile_hv, "sub_subinfo",      newRV_noinc((SV*)sub_subinfo_hv)); 
	hv_stores(profile_hv, "sub_caller",       newRV_noinc((SV*)sub_callers_hv)); 
	hv_stores(profile_hv, "profile_modes",    newRV_noinc((SV*)profile_modes));
	return profile_hv;
}

/***********************************
 * Perl XS Code Below Here         *
 ***********************************/

MODULE = Devel::NYTProf		PACKAGE = Devel::NYTProf		
PROTOTYPES: DISABLE

I32
constant()
	PROTOTYPE:
	ALIAS:
		HAS_FPURGE = HAS_FPURGE_BOOL
	CODE:
	RETVAL = ix;                         
	OUTPUT:
	RETVAL


MODULE = Devel::NYTProf		PACKAGE = DB
PROTOTYPES: DISABLE 

void
DB_profiler(...)
	CODE:
		/* this sub gets aliased as "DB::DB" by NYTProf.pm if use_db_sub is true */
		PERL_UNUSED_VAR(items);
		if (use_db_sub)
			DB_stmt(aTHX_ PL_op);
	  else if (1||trace_level)
			warn("DB called needlessly");

void
set_option(const char *opt, const char *value)

int
init_profiler()
	C_ARGS:
	aTHX

int
enable_profile()
	C_ARGS:
	aTHX

int
disable_profile()
	C_ARGS:
	aTHX

void
finish_profile(...)
	ALIAS:
	_finish = 1
	C_ARGS:
	aTHX


MODULE = Devel::NYTProf		PACKAGE = Devel::NYTProf::Data
PROTOTYPES: DISABLE 

HV*
load_profile_data_from_file(file=NULL)
	char *file;
	CODE:

	if (trace_level)
		warn("reading profile data from file %s\n", file);
	in = fopen(file, "rb");
	if (in == NULL) {
		croak("Failed to open input '%s': %s", file, strerror(errno));
	}
	RETVAL = load_profile_data_from_stream();
	fclose(in);

	OUTPUT:
	RETVAL


