/* vim: ts=8 sw=4 expandtab:
 * ************************************************************************
 * This file is part of the Devel::NYTProf package.
 * Copyright 2008 Adam J. Kaplan, The New York Times Company.
 * Copyright 2009-2010 Tim Bunce, Ireland.
 * Released under the same terms as Perl 5.8
 * See http://search.cpan.org/dist/Devel-NYTProf/
 *
 * Contributors:
 * Tim Bunce, http://www.tim.bunce.name and http://blog.timbunce.org
 * Nicholas Clark,
 * Adam Kaplan, akaplan at nytimes.com
 * Steve Peters, steve at fisharerojo.org
 *
 * ************************************************************************
 * $Id$
 * ************************************************************************
 */
#ifndef WIN32
#define PERL_NO_GET_CONTEXT                       /* we want efficiency */
#endif

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "FileHandle.h"
#include "NYTProf.h"

#ifndef NO_PPPORT_H
#define NEED_eval_pv
#define NEED_grok_number
#define NEED_grok_numeric_radix
#define NEED_newCONSTSUB
#define NEED_newRV_noinc
#define NEED_sv_2pv_flags
#   include "ppport.h"
#endif

/* Until ppport.h gets this:  */
#ifndef memEQs
#  define memEQs(s1, l, s2) \
          (sizeof(s2)-1 == l && memEQ(s1, ("" s2 ""), (sizeof(s2)-1)))
#endif

#ifdef USE_HARD_ASSERT
#undef NDEBUG
#include <assert.h>
#endif

#if !defined(OutCopFILE)
#    define OutCopFILE CopFILE
#endif

#ifndef gv_fetchfile_flags  /* added in perl 5.009005 */
/* we know our uses don't contain embedded nulls, so we just need to copy to a
 * buffer so we can add a trailing null byte */
#define gv_fetchfile_flags(a,b,c)   Perl_gv_fetchfile_flags(aTHX_ a,b,c)
static GV *
Perl_gv_fetchfile_flags(pTHX_ const char *const name, const STRLEN namelen, const U32 flags) {
    char buf[2000];
    if (namelen >= sizeof(buf)-1)
        croak("panic: gv_fetchfile_flags overflow");
    memcpy(buf, name, namelen);
    buf[namelen] = '\0'; /* null-terminate */
    return gv_fetchfile(buf);
}
#endif

#ifndef OP_SETSTATE
#define OP_SETSTATE OP_NEXTSTATE
#endif
#ifndef PERLDBf_SAVESRC
#define PERLDBf_SAVESRC PERLDBf_SUBLINE
#endif
#ifndef PERLDBf_SAVESRC_NOSUBS
#define PERLDBf_SAVESRC_NOSUBS 0
#endif
#ifndef CvISXSUB
#define CvISXSUB CvXSUB
#endif

#if (PERL_VERSION < 8) || ((PERL_VERSION == 8) && (PERL_SUBVERSION < 8))
/* If we're using DB::DB() instead of opcode redirection with an old perl
 * then PL_curcop in DB() will refer to the DB() wrapper in Devel/NYTProf.pm
 * so we'd have to crawl the stack to find the right cop. However, for some
 * reason that I don't pretend to understand the following expression works:
 */
#define PL_curcop_nytprof (opt_use_db_sub ? ((cxstack + cxstack_ix)->blk_oldcop) : PL_curcop)
#else
#define PL_curcop_nytprof PL_curcop
#endif

#define OP_NAME_safe(op) ((op) ? OP_NAME(op) : "NULL")

#ifdef I_SYS_TIME
#include <sys/time.h>
#endif
#include <stdio.h>

#ifdef HAS_ZLIB
#include <zlib.h>
#define default_compression_level 6
#else
#define default_compression_level 0
#endif
#ifndef ZLIB_VERSION
#define ZLIB_VERSION "0"
#endif

#define NYTP_FILE_MAJOR_VERSION 3
#define NYTP_FILE_MINOR_VERSION 0

#define NYTP_START_NO            0
#define NYTP_START_BEGIN         1
#define NYTP_START_CHECK_unused  2  /* not used */
#define NYTP_START_INIT          3
#define NYTP_START_END           4

#define NYTP_OPTf_ADDPID         0x0001 /* append .pid to output filename */
#define NYTP_OPTf_OPTIMIZE       0x0002 /* affect $^P & 0x04 */
#define NYTP_OPTf_SAVESRC        0x0004 /* copy source code lines into profile data */

#define NYTP_FIDf_IS_PMC         0x0001 /* .pm probably really loaded as .pmc */
#define NYTP_FIDf_VIA_STMT       0x0002 /* fid first seen by stmt profiler */
#define NYTP_FIDf_VIA_SUB        0x0004 /* fid first seen by sub profiler */
#define NYTP_FIDf_IS_AUTOSPLIT   0x0008 /* fid is an autosplit (see AutoLoader) */
#define NYTP_FIDf_HAS_SRC        0x0010 /* src is available to profiler */
#define NYTP_FIDf_SAVE_SRC       0x0020 /* src will be saved by profiler, if NYTP_FIDf_HAS_SRC also set */
#define NYTP_FIDf_IS_ALIAS       0x0040 /* fid is clone of the 'parent' fid it was autosplit from */
#define NYTP_FIDf_IS_FAKE        0x0080 /* eg dummy caller of a string eval that doesn't have a filename */

/* indices to elements of the file info array */
#define NYTP_FIDi_FILENAME      0
#define NYTP_FIDi_EVAL_FID      1
#define NYTP_FIDi_EVAL_LINE     2
#define NYTP_FIDi_FID           3
#define NYTP_FIDi_FLAGS         4
#define NYTP_FIDi_FILESIZE      5
#define NYTP_FIDi_FILEMTIME     6
#define NYTP_FIDi_PROFILE       7
#define NYTP_FIDi_EVAL_FI       8
#define NYTP_FIDi_HAS_EVALS     9
#define NYTP_FIDi_SUBS_DEFINED  10
#define NYTP_FIDi_SUBS_CALLED   11

/* indices to elements of the sub call info array */
#define NYTP_SIi_FID         0   /* fid of file sub was defined in */
#define NYTP_SIi_FIRST_LINE  1   /* line number of first line of sub */    
#define NYTP_SIi_LAST_LINE   2   /* line number of last line of sub */    
#define NYTP_SIi_CALL_COUNT  3   /* number of times sub was called */
#define NYTP_SIi_INCL_RTIME  4   /* incl real time in sub */
#define NYTP_SIi_EXCL_RTIME  5   /* excl real time in sub */
#define NYTP_SIi_SUB_NAME    6   /* sub name */
#define NYTP_SIi_PROFILE     7   /* ref to profile object */
#define NYTP_SIi_REC_DEPTH   8   /* max recursion call depth */
#define NYTP_SIi_RECI_RTIME  9   /* recursive incl real time in sub */
#define NYTP_SIi_CALLED_BY  10   /* { fid => { line => [...] } } */
#define NYTP_SIi_elements   11   /* highest index, plus 1 */

/* indices to elements of the sub call info array */
#define NYTP_SCi_CALL_COUNT  0   /* count of calls to sub */    
#define NYTP_SCi_INCL_RTIME  1   /* inclusive real time in sub */    
#define NYTP_SCi_EXCL_RTIME  2   /* exclusive real time in sub */    
#define NYTP_SCi_spare_3     3   /* */
#define NYTP_SCi_spare_4     4   /* */
#define NYTP_SCi_RECI_RTIME  5   /* recursive incl real time in sub */
#define NYTP_SCi_REC_DEPTH   6   /* max recursion call depth */
#define NYTP_SCi_CALLING_SUB 7   /* name of calling sub */
#define NYTP_SCi_elements    8   /* highest index, plus 1 */

#define MAX_HASH_SIZE 512

static int next_fid = 1;         /* 0 is reserved */

/* we're not thread-safe (or even multiplicity safe) yet, so detect and bail */
#ifdef MULTIPLICITY
static PerlInterpreter *orig_my_perl;
#endif

typedef struct hash_entry
{
    unsigned int id;
    void* next_entry;
    char* key;
    unsigned int key_len;
    unsigned int eval_fid;
    unsigned int eval_line_num;
    unsigned int file_size;
    unsigned int file_mtime;
    unsigned int fid_flags;
    char *key_abs;
    void* next_inserted;                          /* linked list in insertion order */
    /* update autosplit logic in get_file_id if fields are added or changed */
} Hash_entry;

typedef struct hash_table
{
    Hash_entry** table;
    unsigned int size;
    Hash_entry* first_inserted;
    Hash_entry* last_inserted;
} Hash_table;

static Hash_table hashtable = { NULL, MAX_HASH_SIZE, NULL, NULL };
/* END Hash table definitions */


/* defaults */
static NYTP_file out;
static NYTP_file in;

/* options and overrides */
static char PROF_output_file[MAXPATHLEN+1] = "nytprof.out";
static unsigned int profile_opts = NYTP_OPTf_OPTIMIZE;
static int profile_start = NYTP_START_BEGIN;      /* when to start profiling */

struct NYTP_int_options_t {
  const char *option_name;
  int option_value;
};

/* XXX boolean options should be moved into profile_opts */
static struct NYTP_int_options_t options[] = {
#define profile_usecputime options[0].option_value
    { "usecputime", 0 },
#define profile_subs options[1].option_value
    { "subs", 1 },                                /* subroutine times */
#define profile_blocks options[2].option_value
    { "blocks", 1 },                              /* block and sub *exclusive* times */
#define profile_leave options[3].option_value
    { "leave", 1 },                               /* correct block end timing */
#define embed_fid_line options[4].option_value
    { "expand", 0 },
#define trace_level options[5].option_value
    { "trace", 0 },
#define opt_use_db_sub options[6].option_value
    { "use_db_sub", 0 },
#define compression_level options[7].option_value
    { "compress", default_compression_level },
#define profile_clock options[8].option_value
    { "clock", -1 },
#define profile_stmts options[9].option_value
    { "stmts", 1 },                              /* statement exclusive times */
#define profile_slowops options[10].option_value
    { "slowops", 2 },                            /* slow opcodes, typically system calls */
#define profile_findcaller options[11].option_value
    { "findcaller", 0 },                         /* find sub caller instead of trusting outer */
#define profile_forkdepth options[12].option_value
    { "forkdepth", -1 },                         /* how many generations of kids to profile */
#define opt_perldb options[13].option_value
    { "perldb", 0 },                             /* force certain PL_perldb value */
#define opt_nameevals options[14].option_value
    { "nameevals", 1 },                          /* change $^P 0x100 bit */
#define opt_nameanonsubs options[15].option_value
    { "nameanonsubs", 1 }                        /* change $^P 0x200 bit */
};

/* time tracking */
static struct tms start_ctime, end_ctime;

#ifdef HAS_CLOCK_GETTIME
/* http://www.freebsd.org/cgi/man.cgi?query=clock_gettime
 * http://webnews.giga.net.tw/article//mailing.freebsd.performance/710
 * http://sean.chittenden.org/news/2008/06/01/
 * Explanation of why gettimeofday() (and presumably CLOCK_REALTIME) may go backwards:
 * http://groups.google.com/group/comp.os.linux.development.apps/tree/browse_frm/thread/dc29071f2417f75f/ac44671fdb35f6db?rnum=1&_done=%2Fgroup%2Fcomp.os.linux.development.apps%2Fbrowse_frm%2Fthread%2Fdc29071f2417f75f%2Fc46264dba0863463%3Flnk%3Dst%26rnum%3D1%26#doc_776f910824bdbee8
 */
typedef struct timespec time_of_day_t;
#  define CLOCK_GETTIME(ts) clock_gettime(profile_clock, ts)
#  define CLOCKS_PER_TICK 10000000                /* 10 million - 100ns */
#  define get_time_of_day(into) CLOCK_GETTIME(&into)
#  define get_ticks_between(s, e, ticks, overflow) STMT_START { \
    overflow = 0; \
    ticks = ((e.tv_sec - s.tv_sec) * CLOCKS_PER_TICK + (e.tv_nsec / 100) - (s.tv_nsec / 100)); \
} STMT_END

#else                                             /* !HAS_CLOCK_GETTIME */

#ifdef HAS_MACH_TIME

#include <mach/mach.h>
#include <mach/mach_time.h>

mach_timebase_info_data_t  our_timebase;
typedef uint64_t time_of_day_t;

#  define CLOCKS_PER_TICK 10000000                /* 10 million - 100ns */
#  define get_time_of_day(into) into = mach_absolute_time()
#  define get_ticks_between(s, e, ticks, overflow) STMT_START { \
    overflow = 0; \
    if( our_timebase.denom == 0 ) mach_timebase_info(&our_timebase); \
    ticks = (e-s) * our_timebase.numer / our_timebase.denom / 100; \
} STMT_END

#else                                             /* !HAS_MACH_TIME */

#ifdef HAS_GETTIMEOFDAY
typedef struct timeval time_of_day_t;
#  define CLOCKS_PER_TICK 1000000                 /* 1 million */
#  define get_time_of_day(into) gettimeofday(&into, NULL)
#  define get_ticks_between(s, e, ticks, overflow) STMT_START { \
    overflow = 0; \
    ticks = ((e.tv_sec - s.tv_sec) * CLOCKS_PER_TICK + e.tv_usec - s.tv_usec); \
} STMT_END
#else
static int (*u2time)(pTHX_ UV *) = 0;
typedef UV time_of_day_t[2];
#  define CLOCKS_PER_TICK 1000000                 /* 1 million */
#  define get_time_of_day(into) (*u2time)(aTHX_ into)
#  define get_ticks_between(s, e, ticks, overflow)  STMT_START { \
    overflow = 0; \
    ticks = ((e[0] - s[0]) * CLOCKS_PER_TICK + e[1] - s[1]); \
} STMT_END
#endif
#endif
#endif

static time_of_day_t start_time;
static time_of_day_t end_time;

static unsigned int last_executed_line;
static unsigned int last_executed_fid;
static        char *last_executed_fileptr;
static unsigned int last_block_line;
static unsigned int last_sub_line;
static unsigned int is_profiling;       /* disable_profile() & enable_profile() */
static Pid_t last_pid;
static NV cumulative_overhead_ticks = 0.0;
static NV cumulative_subr_secs = 0.0;
static UV cumulative_subr_seqn = 0;
static int main_runtime_used = 0;
static SV *DB_INIT_cv;
static SV *DB_fin_cv;

static unsigned int ticks_per_sec = 0;            /* 0 forces error if not set */

static AV *slowop_name_cache;

/* prototypes */
static void output_header(pTHX);
static unsigned int read_int(NYTP_file ifile);
static SV *read_str(pTHX_ NYTP_file ifile, SV *sv);
static unsigned int get_file_id(pTHX_ char*, STRLEN, int created_via);
static void DB_stmt(pTHX_ COP *cop, OP *op);
static void set_option(pTHX_ const char*, const char*);
static int enable_profile(pTHX_ char *file);
static int disable_profile(pTHX);
static void finish_profile(pTHX);
static void open_output_file(pTHX_ char *);
static int reinit_if_forked(pTHX);
static int parse_DBsub_value(pTHX_ SV *sv, STRLEN *filename_len_p, UV *first_line_p, UV *last_line_p);
static void write_cached_fids(void);
static void write_src_of_files(pTHX);
static void write_sub_line_ranges(pTHX);
static void write_sub_callers(pTHX);
static HV *load_profile_data_from_stream(SV* cb);
static AV *store_profile_line_entry(pTHX_ SV *rvav, unsigned int line_num,
                                    NV time, int count, unsigned int fid);

/* copy of original contents of PL_ppaddr */
typedef OP * (CPERLscope(*orig_ppaddr_t))(pTHX);
orig_ppaddr_t *PL_ppaddr_orig;
#define run_original_op(type) CALL_FPTR(PL_ppaddr_orig[type])(aTHX)
static OP *pp_entersub_profiler(pTHX);
static OP *pp_subcall_profiler(pTHX_ int type);
static OP *pp_leave_profiler(pTHX);
static HV *sub_callers_hv;
static HV *pkg_fids_hv;     /* currently just package names */

/* macros for outputing profile data */
#ifndef HAS_GETPPID
#define getppid() 0
#endif

static FILE *logfh;

/* predeclare to set attribute */
static void logwarn(const char *pat, ...) __attribute__format__(__printf__,1,2);
static void
logwarn(const char *pat, ...)
{
    /* we avoid using any perl mechanisms here */
    va_list args;
    va_start(args, pat);
    if (!logfh)
        logfh = stderr;
    vfprintf(logfh, pat, args);
    va_end(args);
}


/***********************************
 * Devel::NYTProf Functions        *
 ***********************************/

static NV
gettimeofday_nv(void)
{
#ifdef HAS_GETTIMEOFDAY
    struct timeval when;
    gettimeofday(&when, (struct timezone *) 0);
    return when.tv_sec + (when.tv_usec / 1000000.0);
#else
    if (u2time) {
        UV time_of_day[2];
        (*u2time)(aTHX_ &time_of_day);
        return time_of_day[0] + (time_of_day[1] / 1000000.0);
    }
    return (NV)time();
#endif
}

/**
 * output file header
 */
static void
output_header(pTHX)
{
    /* $0 - application name */
    SV *const sv = get_sv("0",GV_ADDWARN);
    time_t basetime = PL_basetime;
    /* This comes back with a terminating \n, and we don't want that.  */
    const char *const basetime_str = ctime(&basetime);
    const STRLEN basetime_str_len = strlen(basetime_str);
    const char version[] = STRINGIFY(PERL_REVISION) "."
        STRINGIFY(PERL_VERSION) "." STRINGIFY(PERL_SUBVERSION);
    STRLEN len;
    const char *argv0 = SvPV(sv, len);

    assert(out != NULL);
    /* File header with "magic" string, with file major and minor version */
    NYTP_printf(out, "NYTProf %d %d\n", NYTP_FILE_MAJOR_VERSION, NYTP_FILE_MINOR_VERSION);
    /* Human readable comments and attributes follow
     * comments start with '#', end with '\n', and are discarded
     * attributes start with ':', a word, '=', then the value, then '\n'
     */
    NYTP_write_comment(out, "Perl profile database. Generated by Devel::NYTProf on %.*s",
                       (int)basetime_str_len - 1, basetime_str);

    /* XXX add options, $0, etc, but beware of embedded newlines */
    /* XXX would be good to adopt a proper charset & escaping for these */
    /* $^T */
    NYTP_write_attribute_unsigned(out, STR_WITH_LEN("basetime"), PL_basetime);
    NYTP_write_attribute_string(out, STR_WITH_LEN("xs_version"), STR_WITH_LEN(XS_VERSION));
    NYTP_write_attribute_string(out, STR_WITH_LEN("perl_version"), version, sizeof(version) - 1);
    NYTP_write_attribute_signed(out, STR_WITH_LEN("clock_id"), profile_clock);
    NYTP_write_attribute_unsigned(out, STR_WITH_LEN("ticks_per_sec"), ticks_per_sec);
    NYTP_write_attribute_unsigned(out, STR_WITH_LEN("nv_size"), sizeof(NV));
    NYTP_write_attribute_unsigned(out, STR_WITH_LEN("PL_perldb"), PL_perldb);
    NYTP_write_attribute_string(out, STR_WITH_LEN("application"), argv0, len);

#ifdef HAS_ZLIB
    if (compression_level) {
        const unsigned char tag = NYTP_TAG_START_DEFLATE;
        NYTP_write_comment(out, "Compressed at level %d with zlib %s",
                           compression_level, zlibVersion());
        NYTP_write(out, &tag, sizeof(tag));
        NYTP_start_deflate(out, compression_level);
    }
#endif

    NYTP_write_process_start(out, getpid(), getppid(), gettimeofday_nv());

    write_cached_fids();                          /* empty initially, non-empty after fork */

    NYTP_flush(out);
}

static SV *
read_str(pTHX_ NYTP_file ifile, SV *sv) {
    STRLEN len;
    char *buf;
    unsigned char tag;

    NYTP_read(ifile, &tag, sizeof(tag), "string prefix");

    if (NYTP_TAG_STRING != tag && NYTP_TAG_STRING_UTF8 != tag)
        croak("File format error at offset %ld%s, expected string tag but found %d ('%c')",
              NYTP_tell(ifile)-1, NYTP_type_of_offset(ifile), tag, tag);

    len = read_int(ifile);
    if (sv) {
        SvGROW(sv, len+1);  /* forces SVt_PV */
    }
    else {
        sv = newSV(len+1); /* +1 to force SVt_PV even for 0 length string */
    }
    SvPOK_on(sv);

    buf = SvPV_nolen(sv);
    NYTP_read(ifile, buf, len, "string");
    SvCUR_set(sv, len);
    *SvEND(sv) = '\0';

    if (NYTP_TAG_STRING_UTF8 == tag)
        SvUTF8_on(sv);

    if (trace_level >= 5)
        logwarn("  read string '%.*s'%s\n", (int)len, SvPV_nolen(sv),
            (SvUTF8(sv)) ? " (utf8)" : "");

    return sv;
}


/**
 * An implementation of the djb2 hash function by Dan Bernstein.
 */
static unsigned long
hash (char* _str, unsigned int len)
{
    char* str = _str;
    unsigned long hash = 5381;

    while (len--) {
        /* hash * 33 + c */
        hash = ((hash << 5) + hash) + *str++;
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
static char
hash_op (Hash_entry entry, Hash_entry** retval, bool insert)
{
    unsigned long h = hash(entry.key, entry.key_len) % hashtable.size;

    Hash_entry* found = hashtable.table[h];
    while(NULL != found) {

        if (found->key_len == entry.key_len &&
        memEQ(found->key, entry.key, entry.key_len)) {
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
                memcpy(e->key, entry.key, e->key_len);
                found->next_entry = e;
                *retval = (Hash_entry*)found->next_entry;
                if (hashtable.last_inserted)
                    hashtable.last_inserted->next_inserted = e;
                hashtable.last_inserted = e;
                return 1;
            }
            else {
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
        memcpy(e->key, entry.key, e->key_len);

        *retval =   hashtable.table[h] = e;

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
emit_fid (Hash_entry *fid_info)
{
    char  *file_name     = fid_info->key;
    STRLEN file_name_len = fid_info->key_len;
    if (fid_info->key_abs) {
        file_name = fid_info->key_abs;
        file_name_len = strlen(file_name);
    }

#ifdef WIN32
    /* Make sure we only use forward slashes in filenames */
    if (memchr(file_name, '\\', file_name_len)) {
        STRLEN i;
        char *file_name_copy = (char*)safemalloc(file_name_len);
        for (i=0; i<file_name_len; ++i) {
            char ch = file_name[i];
            file_name_copy[i] = ch == '\\' ? '/' : ch;
        }
        NYTP_write_new_fid(out, fid_info->id, fid_info->eval_fid,
                           fid_info->eval_line_num, fid_info->fid_flags,
                           fid_info->file_size, fid_info->file_mtime,
                           file_name_copy, file_name_len);
        Safefree(file_name_copy);
        return;
    }
#endif

    NYTP_write_new_fid(out, fid_info->id, fid_info->eval_fid,
                       fid_info->eval_line_num, fid_info->fid_flags,
                       fid_info->file_size, fid_info->file_mtime,
                       file_name, file_name_len);
}


/* return true if file is a .pm that was actually loaded as a .pmc */
static int
fid_is_pmc(pTHX_ Hash_entry *fid_info)
{
    int is_pmc = 0;
    char  *file_name     = fid_info->key;
    STRLEN len = fid_info->key_len;
    if (fid_info->key_abs) {
        file_name = fid_info->key_abs;
        len = strlen(file_name);
    }

    if (len > 3 && memEQs(file_name + len - 3, 3, ".pm")) {
        /* ends in .pm, ok, does a newer .pmc exist? */
        /* based on doopen_pm() in perl's pp_ctl.c */
        SV *const pmcsv = newSV(len + 2);
        char *const pmc = SvPVX(pmcsv);
        Stat_t pmstat;
        Stat_t pmcstat;

        memcpy(pmc, file_name, len);
        pmc[len] = 'c';
        pmc[len + 1] = '\0';

        if (PerlLIO_lstat(pmc, &pmcstat) == 0) {
            /* .pmc exists, is it newer than the .pm (if that exists) */

            /* Keys in the fid_info are explicitly written with a terminating
               '\0', so it is safe to pass file_name to a system call.  */
            if (PerlLIO_lstat(file_name, &pmstat) < 0 ||
            pmstat.st_mtime < pmcstat.st_mtime) {
                is_pmc = 1; /* hey, maybe it's Larry working on the perl6 comiler */
            }
        }
        SvREFCNT_dec(pmcsv);
    }

    return is_pmc;
}


static SV *
fmt_fid_flags(pTHX_ int fid_flags, SV *sv) {
    if (!sv)
        sv = sv_newmortal();
    sv_setpv(sv,"");
    if (fid_flags & NYTP_FIDf_IS_PMC)         sv_catpv(sv, "pmc,");
    if (fid_flags & NYTP_FIDf_VIA_STMT)       sv_catpv(sv, "viastmt,");
    if (fid_flags & NYTP_FIDf_VIA_SUB)        sv_catpv(sv, "viasub,");
    if (fid_flags & NYTP_FIDf_IS_AUTOSPLIT)   sv_catpv(sv, "autosplit,");
    if (fid_flags & NYTP_FIDf_HAS_SRC)        sv_catpv(sv, "hassrc,");
    if (fid_flags & NYTP_FIDf_SAVE_SRC)       sv_catpv(sv, "savesrc,");
    if (fid_flags & NYTP_FIDf_IS_ALIAS)       sv_catpv(sv, "alias,");
    if (fid_flags & NYTP_FIDf_IS_FAKE)        sv_catpv(sv, "fake,");
    return sv;
}


static void
write_cached_fids()
{
    Hash_entry *e = hashtable.first_inserted;
    while (e) {
        if ( !(e->fid_flags & NYTP_FIDf_IS_ALIAS) )
            emit_fid(e);
        e = (Hash_entry *)e->next_inserted;
    }
}


static Hash_entry *
find_autosplit_parent(pTHX_ char* file_name)
{
    /* extract basename from file_name, then search for most recent entry
     * in hashtable that has the same basename
     */
    Hash_entry *e = hashtable.first_inserted;
    Hash_entry *match = NULL;
    const char *sep = "/";
    char *base_end   = strstr(file_name, " (autosplit");
    char *base_start = rninstr(file_name, base_end, sep, sep+1);
    STRLEN base_len;
    base_start = (base_start) ? base_start+1 : file_name;
    base_len = base_end - base_start;

    if (trace_level >= 3)
        logwarn("find_autosplit_parent of '%.*s' (%s)\n",
            (int)base_len, base_start, file_name);

    for ( ; e; e = (Hash_entry *)e->next_inserted) {
        char *e_name;

        if (e->fid_flags & NYTP_FIDf_IS_AUTOSPLIT)
            continue;
        if (trace_level >= 4)
            logwarn("find_autosplit_parent: checking '%.*s'\n", e->key_len, e->key);

        /* skip if key is too small to match */
        if (e->key_len < base_len)
            continue;
        /* skip if the last base_len bytes don't match the base name */
        e_name = e->key + e->key_len - base_len;
        if (memcmp(e_name, base_start, base_len) != 0)
            continue;
        /* skip if the char before the matched key isn't a separator */
        if (e->key_len > base_len && *(e_name-1) != *sep)
            continue;

        if (trace_level >= 3)
            logwarn("matched autosplit '%.*s' to parent fid %d '%.*s' (%c|%c)\n",
                (int)base_len, base_start, e->id, e->key_len, e->key, *(e_name-1),*sep);
        match = e;
        /* keep looking, so we'll return the most recently profiled match */
    }

    return match;
}


/**
 * Return a unique persistent id number for a file.
 * If file name has not been seen before
 * then, if created_via is false it returns 0 otherwise it
 * assigns a new id and outputs the file and id to the stream.
 * If the file name is a synthetic name for an eval then
 * get_file_id recurses to process the 'embedded' file name first.
 * The created_via flag bit is stored in the fid info
 * (currently only used as a diagnostic tool)
 */
static unsigned int
get_file_id(pTHX_ char* file_name, STRLEN file_name_len, int created_via)
{

    Hash_entry entry, *found, *parent_entry;
    AV *src_av = Nullav;

    if (0) memset(&entry, 0, sizeof(entry)); /* handy if debugging */
    entry.key = file_name;
    entry.key_len = (unsigned int)file_name_len;

    /* inserted new entry */
    if (1 != hash_op(entry, &found, (bool)(created_via ? 1 : 0))) {
        if (trace_level >= 7) {
            if (found)
                 logwarn("fid %d: %.*s\n",  found->id, found->key_len, found->key);
            else logwarn("fid -: %.*s not profiled\n",  entry.key_len,  entry.key);
        }
        return (found) ? found->id : 0;
    }

    /* if this is a synthetic filename for a string eval
     * ie "(eval 42)[/some/filename.pl:line]"
     * then ensure we've already generated a fid for the underlying
     * filename, and associate that fid with this eval fid
     */
    if ('(' == file_name[0]) {                      /* first char is '(' */
        if (']' == file_name[file_name_len-1]) {    /* last char is ']' */
            char *start = strchr(file_name, '[');
            const char *colon = ":";
            /* can't use strchr here (not nul terminated) so use rninstr */
            char *end = rninstr(file_name, file_name+file_name_len-1, colon, colon+1);

            if (!start || !end || start > end) {    /* should never happen */
                logwarn("NYTProf unsupported filename syntax '%s'\n", file_name);
                return 0;
            }
            ++start;                                /* move past [ */
            /* recurse */
            found->eval_fid = get_file_id(aTHX_ start, end - start, created_via);
            found->eval_line_num = atoi(end+1);
        }
        else if (strnEQ(file_name, "(eval ", 6)) {
            /* strange eval that doesn't have a filename associated */
            /* seen in mod_perl, possibly from eval_sv(sv) api call */
            /* also when nameevals=0 option is in effect */
            char eval_file[] = "/unknown-eval-invoker";
            found->eval_fid = get_file_id(aTHX_ eval_file, sizeof(eval_file) - 1,
                NYTP_FIDf_IS_FAKE | created_via
            );
            found->eval_line_num = 1;
        }
    }

    /* is the file is an autosplit, e.g., has a file_name like
     * "../../lib/POSIX.pm (autosplit into ../../lib/auto/POSIX/errno.al)"
     */
    if ( ')' == file_name[file_name_len-1] && strstr(file_name, " (autosplit ")) {
        found->fid_flags |= NYTP_FIDf_IS_AUTOSPLIT;
    }

    /* if the file is an autosplit
     * then we want it to have the same fid as the file it was split from.
     * Thankfully that file will almost certainly be in the fid hash,
     * so we can find it and copy the details.
     * We do this after the string eval check above in the (untested) hope
     * that string evals inside autoloaded subs get treated properly! XXX
     */
    if (found->fid_flags & NYTP_FIDf_IS_AUTOSPLIT
        && (parent_entry = find_autosplit_parent(aTHX_ file_name))
    ) {
        /* copy some details from parent_entry to found */
        found->id            = parent_entry->id;
        found->eval_fid      = parent_entry->eval_fid;
        found->eval_line_num = parent_entry->eval_line_num;
        found->file_size     = parent_entry->file_size;
        found->file_mtime    = parent_entry->file_mtime;
        found->fid_flags     = parent_entry->fid_flags;
        /* prevent write_cached_fids() from writing this fid */
        found->fid_flags |= NYTP_FIDf_IS_ALIAS;
        /* avoid a gap in the fid sequence */
        --next_fid;
        /* write a log message if tracing */
        if (trace_level >= 2)
            logwarn("Use fid %2u (after %2u:%-4u) %x e%u:%u %.*s %s\n",
                found->id, last_executed_fid, last_executed_line,
                found->fid_flags, found->eval_fid, found->eval_line_num,
                found->key_len, found->key, (found->key_abs) ? found->key_abs : "");
        /* bail out without calling emit_fid() */
        return found->id;
    }

    /* determine absolute path if file_name is relative */
    found->key_abs = NULL;
    if (!found->eval_fid &&
        !(file_name[0] == '-'
         && (file_name_len==1
             || (file_name[1] == 'e' && file_name_len==2))) &&
#ifdef WIN32
        /* XXX should we check for UNC names too? */
        (file_name_len < 3 || !isALPHA(file_name[0]) || file_name[1] != ':' ||
            (file_name[2] != '/' && file_name[2] != '\\'))
#else
        *file_name != '/'
#endif
        )
    {
        char file_name_abs[MAXPATHLEN * 2];
        /* Note that the current directory may have changed
            * between loading the file and profiling it.
            * We don't use realpath() or similar here because we want to
            * keep the view of symlinks etc. as the program saw them.
            */
        if (!getcwd(file_name_abs, sizeof(file_name_abs))) {
            /* eg permission */
            logwarn("getcwd: %s\n", strerror(errno));
        }
        else {
#ifdef WIN32
            char *p = file_name_abs;
            while (*p) {
                if ('\\' == *p)
                    *p = '/';
                ++p;
            }
            if (p[-1] != '/')
#else
            if (strNE(file_name_abs, "/"))
#endif
            {
                if (strnEQ(file_name, "./", 2)) {
                    ++file_name;
                } else {
#ifndef VMS
                    strcat(file_name_abs, "/");
#endif
                }
            }
            strncat(file_name_abs, file_name, file_name_len);
            found->key_abs = strdup(file_name_abs);
        }
    }

    if (fid_is_pmc(aTHX_ found))
        found->fid_flags |= NYTP_FIDf_IS_PMC;
    found->fid_flags |= created_via; /* NYTP_FIDf_VIA_STMT or NYTP_FIDf_VIA_SUB */

    /* is source code available? */
    /* source only available if PERLDB_LINE or PERLDB_SAVESRC is true */
    /* which we set if savesrc option is enabled */
    if ( (src_av = GvAV(gv_fetchfile_flags(found->key, found->key_len, 0))) )
        found->fid_flags |= NYTP_FIDf_HAS_SRC;

    /* if it's a string eval or a synthetic filename from CODE ref in @INC,
     * or the command line -e '...code...'
     * then we'd like to save the src (NYTP_FIDf_HAS_SRC) if it's available
     */
    if (found->eval_fid
    || (found->key_len > 10 && found->key[9] == 'x' && strnEQ(found->key, "/loader/0x", 10))
    || (found->key[0] == '-' && (found->key_len == 1 ||
                                 (found->key[1] == 'e' && found->key_len == 2)))
    || (profile_opts & NYTP_OPTf_SAVESRC)
    ) {
        found->fid_flags |= NYTP_FIDf_SAVE_SRC;
    }

    emit_fid(found);

    if (trace_level >= 2) {
        /* including last_executed_fid can be handy for tracking down how
            * a file got loaded */
        logwarn("New fid %2u (after %2u:%-4u) 0x%02x e%u:%u %.*s %s %s,%s\n",
            found->id, last_executed_fid, last_executed_line,
            found->fid_flags, found->eval_fid, found->eval_line_num,
            found->key_len, found->key, (found->key_abs) ? found->key_abs : "",
            (found->fid_flags & NYTP_FIDf_HAS_SRC)  ? "has src" : "no src",
            (found->fid_flags & NYTP_FIDf_SAVE_SRC) ? "save src" : "nosave src"
        );
    }

    return found->id;
}

static UV
uv_from_av(pTHX_ AV *av, int idx, UV default_uv)
{
    SV **svp = av_fetch(av, idx, 0);
    UV uv = (!svp || !SvOK(*svp)) ? default_uv : SvUV(*svp);
    return uv;
}

static NV
nv_from_av(pTHX_ AV *av, int idx, NV default_nv)
{
    SV **svp = av_fetch(av, idx, 0);
    NV nv = (!svp || !SvOK(*svp)) ? default_nv : SvNV(*svp);
    return nv;
}


static const char *
cx_block_type(PERL_CONTEXT *cx) {
    switch (CxTYPE(cx)) {
    case CXt_NULL:              return "CXt_NULL";
    case CXt_SUB:               return "CXt_SUB";
    case CXt_FORMAT:            return "CXt_FORMAT";
    case CXt_EVAL:              return "CXt_EVAL";
    case CXt_SUBST:             return "CXt_SUBST";
#ifdef CXt_WHEN
    case CXt_WHEN:              return "CXt_WHEN";
#endif
    case CXt_BLOCK:             return "CXt_BLOCK";
#ifdef CXt_GIVEN
    case CXt_GIVEN:             return "CXt_GIVEN";
#endif
#ifdef CXt_LOOP_FOR
    case CXt_LOOP_FOR:          return "CXt_LOOP_FOR";
#endif
#ifdef CXt_LOOP_PLAIN
    case CXt_LOOP_PLAIN:        return "CXt_LOOP_PLAIN";
#endif
#ifdef CXt_LOOP_LAZYSV
    case CXt_LOOP_LAZYSV:       return "CXt_LOOP_LAZYSV";
#endif
#ifdef CXt_LOOP_LAZYIV
    case CXt_LOOP_LAZYIV:       return "CXt_LOOP_LAZYIV";
#endif
    }
    return "CXt_???";
}


/* based on S_dopoptosub_at() from perl pp_ctl.c */
static int
dopopcx_at(pTHX_ PERL_CONTEXT *cxstk, I32 startingblock, UV cx_type_mask)
{
    I32 i;
    register PERL_CONTEXT *cx;
    for (i = startingblock; i >= 0; i--) {
        UV type_bit;
        cx = &cxstk[i];
        type_bit = 1 << CxTYPE(cx);
        if (type_bit & cx_type_mask)
            return i;
    }
    return i;                                     /* == -1 */
}


static COP *
start_cop_of_context(pTHX_ PERL_CONTEXT *cx)
{
    OP *start_op, *o;
    int type;
    int trace = 6;

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
#  if (PERL_VERSION < 10) || (PERL_VERSION == 9 && !defined(CX_LOOP_NEXTOP_GET))
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
        case CXt_SUBST:                           /* FALLTHRU */
        case CXt_NULL:                            /* FALLTHRU */
        default:
            start_op = NULL;
            break;
    }
    if (!start_op) {
        if (trace_level >= trace)
            logwarn("\tstart_cop_of_context: can't find start of %s\n",
                cx_block_type(cx));
        return NULL;
    }
    /* find next cop from OP */
    o = start_op;
    while ( o && (type = (o->op_type) ? o->op_type : (int)o->op_targ) ) {
        if (type == OP_NEXTSTATE || type == OP_SETSTATE || type == OP_DBSTATE) {
            if (trace_level >= trace)
                logwarn("\tstart_cop_of_context %s is %s line %d of %s\n",
                    cx_block_type(cx), OP_NAME(o), (int)CopLINE((COP*)o),
                    OutCopFILE((COP*)o));
            return (COP*)o;
        }
        /* should never get here but we do */
        if (trace_level >= trace) {
            logwarn("\tstart_cop_of_context %s op '%s' isn't a cop\n",
                cx_block_type(cx), OP_NAME(o));
            if (trace_level >  trace)
                do_op_dump(1, PerlIO_stderr(), o);
        }
        o = o->op_next;
    }
    if (trace_level >= 3) {
        logwarn("\tstart_cop_of_context: can't find next cop for %s line %ld\n",
            cx_block_type(cx), (long)CopLINE(PL_curcop_nytprof));
        do_op_dump(1, PerlIO_stderr(), start_op);
    }
    return NULL;
}


/* Walk up the context stack calling callback
 * return first context that callback returns true for
 * else return null.
 * UV cx_type_mask is a bit flag that specifies what kinds of contexts the
 * callback should be called for: (cx_type_mask & (1 << CxTYPE(cx)))
 * Use ~0 to stop at all contexts.
 * The callback is called with the context pointer and a pointer to
 * a copy of the UV cx_type_mask argument (so it can change it on the fly).
 */
static PERL_CONTEXT *
visit_contexts(pTHX_ UV cx_type_mask, int (*callback)(pTHX_ PERL_CONTEXT *cx,
UV *cx_type_mask_ptr))
{
    /* modelled on pp_caller() in pp_ctl.c */
    register I32 cxix = cxstack_ix;
    register PERL_CONTEXT *cx = NULL;
    register PERL_CONTEXT *ccstack = cxstack;
    PERL_SI *top_si = PL_curstackinfo;

    if (trace_level >= 6)
        logwarn("visit_contexts: \n");

    while (1) {
        /* we may be in a higher stacklevel, so dig down deeper */
        /* XXX so we'll miss code in sort blocks and signals?   */
        /* callback should perhaps be moved to dopopcx_at */
        while (cxix < 0 && top_si->si_type != PERLSI_MAIN) {
            if (trace_level >= 6)
                logwarn("Not on main stack (type %d); digging top_si %p->%p, ccstack %p->%p\n",
                    (int)top_si->si_type, (void*)top_si, (void*)top_si->si_prev,
                    (void*)ccstack, (void*)top_si->si_cxstack);
            top_si  = top_si->si_prev;
            ccstack = top_si->si_cxstack;
            cxix = dopopcx_at(aTHX_ ccstack, top_si->si_cxix, cx_type_mask);
        }
        if (cxix < 0 || (cxix == 0 && !top_si->si_prev)) {
            /* cxix==0 && !top_si->si_prev => top-level BLOCK */
            if (trace_level >= 5)
                logwarn("visit_contexts: reached top of context stack\n");
            return NULL;
        }
        cx = &ccstack[cxix];
        if (trace_level >= 5)
            logwarn("visit_context: %s cxix %d (si_prev %p)\n",
                cx_block_type(cx), (int)cxix, (void*)top_si->si_prev);
        if (callback(aTHX_ cx, &cx_type_mask))
            return cx;
        /* no joy, look further */
        cxix = dopopcx_at(aTHX_ ccstack, cxix - 1, cx_type_mask);
    }
    return NULL;                                  /* not reached */
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


static int
_check_context(pTHX_ PERL_CONTEXT *cx, UV *cx_type_mask_ptr)
{
    COP *near_cop;
    PERL_UNUSED_ARG(cx_type_mask_ptr);

    if (CxTYPE(cx) == CXt_SUB) {
        if (PL_debstash && CvSTASH(cx->blk_sub.cv) == PL_debstash)
            return 0;                             /* skip subs in DB package */

        near_cop = start_cop_of_context(aTHX_ cx);

        /* only use the cop if it's in the same file */
        if (_cop_in_same_file(near_cop, PL_curcop_nytprof)) {
            last_sub_line = CopLINE(near_cop);
            /* treat sub as a block if we've not found a block yet */
            if (!last_block_line)
                last_block_line = last_sub_line;
        }

        if (trace_level >= 6) {
            GV *sv = CvGV(cx->blk_sub.cv);
            logwarn("\tat %d: block %d sub %d for %s %s\n",
                last_executed_line, last_block_line, last_sub_line,
                cx_block_type(cx), (sv) ? GvNAME(sv) : "");
            if (trace_level >= 9)
                sv_dump((SV*)cx->blk_sub.cv);
        }

        return 1;                                 /* stop looking */
    }

    /* NULL, EVAL, LOOP, SUBST, BLOCK context */
    if (trace_level >= 6)
        logwarn("\t%s\n", cx_block_type(cx));

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
        if (trace_level >= 5)
            logwarn("at %d: %s in different file (%s, %s)\n",
                last_executed_line, cx_block_type(cx),
                OutCopFILE(near_cop), OutCopFILE(PL_curcop_nytprof));
        return 1;                                 /* stop looking */
    }

    last_block_line = CopLINE(near_cop);
    if (trace_level >= 5)
        logwarn("\tat %d: block %d for %s\n",
            last_executed_line, last_block_line, cx_block_type(cx));
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
static void
DB_stmt(pTHX_ COP *cop, OP *op)
{
    int saved_errno;
    char *file;
    long elapsed, overflow;

    if (!is_profiling || !profile_stmts)
        return;
#ifdef MULTIPLICITY
    if (my_perl != orig_my_perl)
        return;
#endif

    saved_errno = errno;

    if (profile_usecputime) {
        times(&end_ctime);
        overflow = 0;                             /* XXX */
        elapsed = end_ctime.tms_utime - start_ctime.tms_utime
                + end_ctime.tms_stime - start_ctime.tms_stime;
    }
    else {
        get_time_of_day(end_time);
        get_ticks_between(start_time, end_time, elapsed, overflow);
    }
    if (overflow)                                 /* XXX later output overflow to file */
        logwarn("profile time overflow of %ld seconds discarded\n", overflow);

    reinit_if_forked(aTHX);

    if (last_executed_fid) {
        if (profile_blocks)
            NYTP_write_time_block(out, elapsed, last_executed_fid,
                                  last_executed_line, last_block_line,
                                  last_sub_line);
        else 
            NYTP_write_time_line(out, elapsed, last_executed_fid,
                                 last_executed_line);

        if (trace_level >= 4)
            logwarn("Wrote %d:%-4d %2ld ticks (%u, %u)\n", last_executed_fid,
                last_executed_line, elapsed, last_block_line, last_sub_line);
    }

    if (!cop)
        cop = PL_curcop_nytprof;
    if ( (last_executed_line = CopLINE(cop)) == 0 ) {
        /* Might be a cop that has been optimised away.  We can try to find such a
         * cop by searching through the optree starting from the sibling of PL_curcop.
         * See Perl_vmess in perl's util.c for how warn("...") finds the line number.
         */
        cop = (COP*)closest_cop(aTHX_ cop, cop->op_sibling);
        if (!cop)
            cop = PL_curcop_nytprof;
        last_executed_line = CopLINE(cop);
        if (!last_executed_line) {
            /* perl options, like -n, -p, -Mfoo etc can cause this as perl effectively
             * treats those as 'line 0', so we try not to warn in those cases.
             */
            char *pkg_name = CopSTASHPV(cop);
            int is_preamble = (PL_scopestack_ix <= 6 && strEQ(pkg_name,"main"));

            /* op is null when called via finish_profile called by END */
            if (!is_preamble && op) {
                logwarn("Unable to determine line number in %s\n", OutCopFILE(cop));
                if (trace_level > 5)
                    do_op_dump(1, PerlIO_stderr(), (OP*)cop);
            }
            last_executed_line = 1;               /* don't want zero line numbers in data */
        }
    }

    file = OutCopFILE(cop);
    if (!last_executed_fid) {                     /* first time */
        if (trace_level >= 1) {
            logwarn("~ first statement profiled at line %d of %s, pid %ld\n",
                (int)CopLINE(cop), OutCopFILE(cop), (long)getpid());
        }
    }
    if (file != last_executed_fileptr) { /* cache (hit ratio ~50% e.g. for perlcritic) */
        last_executed_fileptr = file;
        last_executed_fid = get_file_id(aTHX_ file, strlen(file), NYTP_FIDf_VIA_STMT);
    }

    if (trace_level >= 7)
        logwarn("     @%d:%-4d %s\n", last_executed_fid, last_executed_line,
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

    if (profile_usecputime) {
        times(&start_ctime);
        /* insufficient accuracy for cumulative_overhead_ticks */
    }
    else {
        get_time_of_day(start_time);

        /* measure time we've spent measuring so we can discount it */
        get_ticks_between(end_time, start_time, elapsed, overflow);
        cumulative_overhead_ticks += elapsed;
    }

    SETERRNO(saved_errno, 0);
    return;
}


static void
DB_leave(pTHX_ OP *op)
{
    int saved_errno = errno;
    unsigned int prev_last_executed_fid  = last_executed_fid;
    unsigned int prev_last_executed_line = last_executed_line;
    const unsigned char tag = NYTP_TAG_DISCOUNT;

    /* Called _after_ ops that indicate we've completed a statement
     * and are returning into the middle of some outer statement.
     * Used to ensure that time between now and the _next_ statement
     * being entered, is allocated to the outer statement we've
     * returned into and not the previous statement.
     * PL_curcop has already been updated.
     */

    if (!is_profiling || !out || !profile_stmts)
        return;
#ifdef MULTIPLICITY
    if (my_perl != orig_my_perl)
        return;
#endif

    /* measure and output end time of previous statement
     * (earlier than it would have been done)
     * and switch back to measuring the 'calling' statement
     */
    DB_stmt(aTHX_ NULL, op);

    /* output a 'discount' marker to indicate the next statement time shouldn't
     * increment the count (because the time is not for a new statement but simply
     * a continuation of a previously counted statement).
     */
    NYTP_write(out, &tag, sizeof(tag));

    /* special cases */
    if (last_executed_line == prev_last_executed_line
    &&  last_executed_fid  == prev_last_executed_fid
    ) {
        /* XXX OP_UNSTACK needs help */
    }

    if (trace_level >= 4) {
        logwarn("left %u:%u back to %s at %u:%u (b%u s%u) - discounting next statement%s\n",
            prev_last_executed_fid, prev_last_executed_line,
            OP_NAME_safe(op),
            last_executed_fid, last_executed_line, last_block_line, last_sub_line,
            (op) ? "" : ", LEAVING PERL"
        );
    }

    SETERRNO(saved_errno, 0);
}


/**
 * Sets or toggles the option specified by 'option'.
 */
static void
set_option(pTHX_ const char* option, const char* value)
{

    if (strEQ(option, "file")) {
        strncpy(PROF_output_file, value, MAXPATHLEN);
    }
    else if (strEQ(option, "log")) {
        FILE *fp = fopen(value, "a");
        if (!fp) {
            logwarn("Can't open log file '%s' for writing: %s\n",
                value, strerror(errno));
            return;
        }
        logfh = fp;
    }
    else if (strEQ(option, "start")) {
        if      (strEQ(value,"begin")) profile_start = NYTP_START_BEGIN;
        else if (strEQ(value,"init"))  profile_start = NYTP_START_INIT;
        else if (strEQ(value,"end"))   profile_start = NYTP_START_END;
        else if (strEQ(value,"no"))    profile_start = NYTP_START_NO;
        else croak("NYTProf option 'start' has invalid value '%s'\n", value);
    }
    else if (strEQ(option, "addpid")) {
        profile_opts = (atoi(value))
            ? profile_opts |  NYTP_OPTf_ADDPID
            : profile_opts & ~NYTP_OPTf_ADDPID;
    }
    else if (strEQ(option, "optimize") || strEQ(option, "optimise")) {
        profile_opts = (atoi(value))
            ? profile_opts |  NYTP_OPTf_OPTIMIZE
            : profile_opts & ~NYTP_OPTf_OPTIMIZE;
    }
    else if (strEQ(option, "savesrc")) {
        profile_opts = (atoi(value))
            ? profile_opts |  NYTP_OPTf_SAVESRC
            : profile_opts & ~NYTP_OPTf_SAVESRC;
    }
    else if (strEQ(option, "endatexit")) {
        if (atoi(value))
            PL_exit_flags |= PERL_EXIT_DESTRUCT_END;
    }
    else {
        struct NYTP_int_options_t *opt_p = options;
        const struct NYTP_int_options_t *const opt_end
            = options + sizeof(options) / sizeof (struct NYTP_int_options_t);
        bool found = FALSE;
        do {
            if (strEQ(option, opt_p->option_name)) {
                opt_p->option_value = strtol(value, NULL, 0);
                found = TRUE;
                break;
            }
        } while (++opt_p < opt_end);
        if (!found) {
            logwarn("Unknown NYTProf option: '%s'\n", option);
            return;
        }
    }
    if (trace_level)
        logwarn("# %s=%s\n", option, value);
}


/**
 * Open the output file. This is encapsulated because the code can be reused
 * without the environment parsing overhead after each fork.
 */
static void
open_output_file(pTHX_ char *filename)
{
    char filename_buf[MAXPATHLEN];
    /* 'x' is a GNU C lib extension for O_EXCL which gives us a little
     * extra protection, but it isn't POSIX compliant */
    const char *mode = "wbx";
    /* most systems that don't support it will silently ignore it
     * but for some we need to remove it to avoid an error */
#ifdef WIN32
    mode = "wb";
#endif
#ifdef VMS
    mode = "wb";
#endif

    if ((profile_opts & NYTP_OPTf_ADDPID)
    || out /* already opened so assume forking */
    ) {  
        sprintf(filename_buf, "%s.%d", filename, getpid());
        filename = filename_buf;
        /* caller is expected to have purged/closed old out if appropriate */
    }

    /* some protection against multiple processes writing to the same file */
    unlink(filename);   /* throw away any previous file */

    out = NYTP_open(filename, mode);
    if (!out) {
        int fopen_errno = errno;
        const char *hint = "";
        if (fopen_errno==EEXIST && !(profile_opts & NYTP_OPTf_ADDPID))
            hint = " (enable addpid option to protect against concurrent writes)";
        disable_profile(aTHX);
        croak("Failed to open output '%s': %s%s", filename, strerror(fopen_errno), hint);
    }
    if (trace_level >= 1)
        logwarn("~ opened %s\n", filename);

    output_header(aTHX);
}


static void
close_output_file(pTHX) {
    int result;
    if (!out)
        return;

    write_src_of_files(aTHX);
    write_sub_line_ranges(aTHX);
    write_sub_callers(aTHX);
    /* mark end of profile data for last_pid pid
     * which is the pid that this file relates to
     */
    NYTP_write_process_end(out, last_pid, gettimeofday_nv());

    if ((result = NYTP_close(out, 0)))
        logwarn("Error closing profile data file: %s\n", strerror(result));
    out = NULL;
}


static int
reinit_if_forked(pTHX)
{
    int open_new_file;

    if (getpid() == last_pid)
        return 0; /* not forked */

    /* we're now the child process */
    if (trace_level >= 1)
        logwarn("~ new pid %d (was %d) forkdepth %d\n", getpid(), last_pid, profile_forkdepth);

    /* reset state */
    last_pid = getpid();
    last_executed_fileptr = NULL;
    last_executed_fid = 0; /* don't count the fork in the child */
    if (sub_callers_hv)
        hv_clear(sub_callers_hv);

    open_new_file = (out) ? 1 : 0;
    if (open_new_file) {
        /* data that was unflushed in the parent when it forked
        * is now duplicated unflushed in this child,
        * so discard it when we close the inherited filehandle.
        */
        int result = NYTP_close(out, 1);
        if (result)
            logwarn("Error closing profile data file: %s\n", strerror(result));
        out = NULL;
        /* if we fork while profiling then ensure we'll get a distinct filename */
        profile_opts |= NYTP_OPTf_ADDPID;
    }

    if (profile_forkdepth == 0) { /* parent doesn't want children profiled */
        disable_profile(aTHX);
        open_new_file = 0;
    }
    else /* count down another generation */
        --profile_forkdepth;

    if (open_new_file)
        open_output_file(aTHX_ PROF_output_file);

    return 1;                                     /* have forked */
}


/******************************************
 * Sub caller and inclusive time tracking
 ******************************************/

static AV *
new_sub_call_info_av(pTHX)
{
    AV *av = newAV();
    av_store(av, NYTP_SCi_CALL_COUNT, newSVuv(1));
    av_store(av, NYTP_SCi_INCL_RTIME, newSVnv(0.0));
    av_store(av, NYTP_SCi_EXCL_RTIME, newSVnv(0.0));
    /* others allocated when needed */
    return av;
}

/* subroutine profiler subroutine entry structure. Represents a call
 * from one sub to another (the arc between the nodes, if you like)
 */
typedef struct subr_entry_st subr_entry_t;
struct subr_entry_st {
    unsigned int  already_counted;
    unsigned int  subr_prof_depth;
    long unsigned subr_call_seqn;
    I32 prev_subr_entry_ix; /* ix to callers subr_entry */

    time_of_day_t initial_call_timeofday;
    struct tms    initial_call_cputimes;
    NV            initial_overhead_ticks;
    NV            initial_subr_secs;

    unsigned int  caller_fid;
    int           caller_line;
    const char   *caller_subpkg_pv;
    SV           *caller_subnam_sv;

    CV           *called_cv;
    int           called_cv_depth;
    const char   *called_is_xs;         /* NULL, "xsub", or "syop" */
    const char   *called_subpkg_pv;
    SV           *called_subnam_sv;
    /* ensure all items are initialized in first phase of pp_subcall_profiler */
};

/* save stack index to the current subroutine entry structure */
static I32 subr_entry_ix = 0;

#define subr_entry_ix_ptr(ix) ((ix) ? SSPTR(ix, subr_entry_t *) : NULL)


static void
append_linenum_to_begin(pTHX_ subr_entry_t *subr_entry) {
    UV line = 0;
    SV *fullnamesv;
    SV *DBsv;
    char *subname = SvPVX(subr_entry->called_subnam_sv);
    STRLEN pkg_len;
    STRLEN total_len;

    /* If sub is a BEGIN then append the line number to our name
     * so multiple BEGINs (either explicit or implicit, e.g., "use")
     * in the same file/package can be distinguished.
     */
    if (!subname || *subname != 'B' || strNE(subname,"BEGIN"))
        return;

    /* get, and delete, the entry for this sub in the PL_DBsub hash */
    pkg_len = strlen(subr_entry->called_subpkg_pv);
    total_len = pkg_len + 2 /* :: */  + 5; /* BEGIN */
    fullnamesv = newSV(total_len + 1); /* +1 for '\0' */
    memcpy(SvPVX(fullnamesv), subr_entry->called_subpkg_pv, pkg_len);
    memcpy(SvPVX(fullnamesv) + pkg_len, "::BEGIN", 7 + 1); /* + 1 for '\0' */
    SvCUR_set(fullnamesv, total_len);
    SvPOK_on(fullnamesv);
    DBsv = hv_delete(GvHV(PL_DBsub), SvPVX(fullnamesv), total_len, 1);

    if (DBsv && parse_DBsub_value(aTHX_ DBsv, NULL, &line, NULL)) {
        SvREFCNT_inc(DBsv); /* was made mortal by hv_delete */
        sv_catpvf(fullnamesv,                   "@%u", (unsigned int)line);
        /* As we know the length of fullnamesv *before* the concatenation, we
           can calculate the length and offset of the formatted addition, and
           hence directly string append it, rather than duplicating the call to
           a *printf function.  */
        sv_catpvn(subr_entry->called_subnam_sv, SvPVX(fullnamesv) + total_len,
                  SvCUR(fullnamesv) - total_len);
        (void) hv_store(GvHV(PL_DBsub), SvPV_nolen(fullnamesv), SvCUR(fullnamesv), DBsv, 0);
    }
    SvREFCNT_dec(fullnamesv);
}


static char *
subr_entry_summary(pTHX_ subr_entry_t *subr_entry, int state)
{
    static char buf[80]; /* XXX */
    sprintf(buf, "(seix %d%s%d, ac%u)",
        (int)subr_entry->prev_subr_entry_ix,
        (state) ? "<-" : "->",
        (int)subr_entry_ix,
        subr_entry->already_counted
    );
    return buf;
}


static void
subr_entry_destroy(pTHX_ subr_entry_t *subr_entry)
{
    if ((trace_level >= 6 || subr_entry->already_counted>1)
        /* ignore the typical second (fallback) destroy */
        && !(subr_entry->prev_subr_entry_ix == subr_entry_ix && subr_entry->already_counted==1)
    ) {
        logwarn("%2d <<     %s::%s done %s\n",
            subr_entry->subr_prof_depth,
            subr_entry->called_subpkg_pv,
            (subr_entry->called_subnam_sv && SvOK(subr_entry->called_subnam_sv))
                ? SvPV_nolen(subr_entry->called_subnam_sv)
                : "?",
            subr_entry_summary(aTHX_ subr_entry, 1));
    }
    if (subr_entry->caller_subnam_sv) {
        sv_free(subr_entry->caller_subnam_sv);
        subr_entry->caller_subnam_sv = Nullsv;
    }
    if (subr_entry->called_subnam_sv) {
        sv_free(subr_entry->called_subnam_sv);
        subr_entry->called_subnam_sv = Nullsv;
    }
    if (subr_entry->prev_subr_entry_ix <= subr_entry_ix)
        subr_entry_ix = subr_entry->prev_subr_entry_ix;
    else
        logwarn("skipped attempt to raise subr_entry_ix from %d to %d\n",
            (int)subr_entry_ix, (int)subr_entry->prev_subr_entry_ix);
}


static void
incr_sub_inclusive_time(pTHX_ subr_entry_t *subr_entry)
{
    int saved_errno = errno;
    char called_subname_pv[500];    /* XXX */
    char *called_subname_pv_end = called_subname_pv;
    char subr_call_key[500]; /* XXX */
    int subr_call_key_len;
    NV  overhead_ticks, called_sub_secs;
    SV *incl_time_sv, *excl_time_sv;
    NV  incl_subr_sec, excl_subr_sec;
    SV *sv_tmp;
    AV *subr_call_av;

    if (subr_entry->called_subnam_sv == &PL_sv_undef) {
        if (trace_level)
            logwarn("Don't know name of called sub, assuming xsub/builtin exited via an exception (which isn't handled yet)\n");
        subr_entry->already_counted++;
    }

    /* For xsubs we get called both explicitly when the xsub returns, and by
     * the destructor. (That way if the xsub leaves via an exception then we'll
     * still get called, albeit a little later than we'd like.)
     */
    if (subr_entry->already_counted) {
        subr_entry_destroy(aTHX_ subr_entry);
        return;
    }
    subr_entry->already_counted++;

    /* statement overheads we've accumulated since we entered the sub */
    overhead_ticks = cumulative_overhead_ticks - subr_entry->initial_overhead_ticks;
    /* seconds spent in subroutines called by this subroutine */
    called_sub_secs = (cumulative_subr_secs - subr_entry->initial_subr_secs);

    if (profile_usecputime) {
        struct tms call_end_ctime;
        long ticks;

        times(&call_end_ctime);
        ticks = (call_end_ctime.tms_utime - subr_entry->initial_call_cputimes.tms_utime)
              + (call_end_ctime.tms_stime - subr_entry->initial_call_cputimes.tms_stime);
        /* ignore overhead_ticks when using cputime because the resolution is so poor */
        incl_subr_sec = (ticks / (NV)PL_clocktick);
    }
    else {
        time_of_day_t sub_end_time;
        long ticks, overflow;

        /* calculate ticks since we entered the sub */
        get_time_of_day(sub_end_time);
        get_ticks_between(subr_entry->initial_call_timeofday, sub_end_time, ticks, overflow);

        incl_subr_sec = overflow + (ticks / (NV)CLOCKS_PER_TICK);
        /* subtract statement measurement overheads */
        incl_subr_sec -= (overhead_ticks / CLOCKS_PER_TICK);
    }
    /* exclusive = inclusive - time spent in subroutines called by this subroutine */
    excl_subr_sec = incl_subr_sec - called_sub_secs;

    subr_call_key_len = sprintf(subr_call_key, "%s::%s[%u:%d]",
        subr_entry->caller_subpkg_pv,
        (subr_entry->caller_subnam_sv) ? SvPV_nolen(subr_entry->caller_subnam_sv) : "(null)",
        subr_entry->caller_fid, subr_entry->caller_line);
    if (subr_call_key_len >= sizeof(subr_call_key))
        croak("panic: NYTProf buffer overflow on %s\n", subr_call_key);

    /* compose called_subname_pv as "${pkg}::${sub}" avoiding sprintf */
    STMT_START {
        STRLEN len;
        const char *p;

        p = subr_entry->called_subpkg_pv;
        while (*p)
            *called_subname_pv_end++ = *p++;
        *called_subname_pv_end++ = ':';
        *called_subname_pv_end++ = ':';
        if (subr_entry->called_subnam_sv) {
            /* We create this SV, so we know that it is well-formed, and has a
               trailing '\0'  */
            p = SvPV(subr_entry->called_subnam_sv, len);
        }
        else {
            /* C string constants have a trailing '\0'.  */
            p = "(null)"; len = 6;
        }
        memcpy(called_subname_pv_end, p, len + 1);
        called_subname_pv_end += len;
        if (called_subname_pv_end >= called_subname_pv+sizeof(called_subname_pv))
            croak("panic: called_subname_pv buffer overflow on '%s'\n", called_subname_pv);
    } STMT_END;

    /* { called_subname => { "caller_subname[fid:line]" => [ count, incl_time, ... ] } } */
    sv_tmp = *hv_fetch(sub_callers_hv, called_subname_pv, called_subname_pv_end - called_subname_pv, 1);

    if (!SvROK(sv_tmp)) { /* autoviv hash ref - is first call of this called subname from anywhere */
        HV *hv = newHV();
        sv_setsv(sv_tmp, newRV_noinc((SV *)hv));

        if (subr_entry->called_is_xs) {
            /* create dummy item with fid=0 & line=0 to act as flag to indicate xs */
            AV *av = new_sub_call_info_av(aTHX);
            av_store(av, NYTP_SCi_CALL_COUNT, newSVuv(0));
            sv_setsv(*hv_fetch(hv, "[0:0]", 5, 1), newRV_noinc((SV *)av));

            if (   ('s' == *subr_entry->called_is_xs) /* "sop" (slowop) */
                || (subr_entry->called_cv && SvTYPE(subr_entry->called_cv) == SVt_PVCV)
            ) {
                /* We just use an empty string as the filename for xsubs
                    * because CvFILE() isn't reliable on perl 5.8.[78]
                    * and the name of the .c file isn't very useful anyway.
                    * The reader can try to associate the xsubs with the
                    * corresonding .pm file using the package part of the subname.
                    */
                SV *sv = *hv_fetch(GvHV(PL_DBsub), called_subname_pv, called_subname_pv_end - called_subname_pv, 1);
                if (!SvOK(sv))
                    sv_setpvs(sv, ":0-0"); /* empty file name */
                if (trace_level >= 2)
                    logwarn("Adding fake DBsub entry for '%s' xsub\n", called_subname_pv);
            }
        }
    }

    /* drill-down to array of sub call information for this subr_call_key */
    sv_tmp = *hv_fetch((HV*)SvRV(sv_tmp), subr_call_key, subr_call_key_len, 1);
    if (!SvROK(sv_tmp)) { /* first call from this subname[fid:line] - autoviv array ref */
        subr_call_av = new_sub_call_info_av(aTHX);

        sv_setsv(sv_tmp, newRV_noinc((SV *)subr_call_av));

        if (subr_entry->called_subpkg_pv) { /* note that a sub in this package was called */
            SV *pf_sv = *hv_fetch(pkg_fids_hv, subr_entry->called_subpkg_pv, (I32)strlen(subr_entry->called_subpkg_pv), 1);
            if (SvTYPE(pf_sv) == SVt_NULL) { /* log when first created */
                sv_upgrade(pf_sv, SVt_PV);
                if (trace_level >= 5)
                    logwarn("Noting that subs in package '%s' were called\n",
                        subr_entry->called_subpkg_pv);
            }
        }
    }
    else {
        subr_call_av = (AV *)SvRV(sv_tmp);
        sv_inc(AvARRAY(subr_call_av)[NYTP_SCi_CALL_COUNT]);
    }

    if (trace_level >= 4)
        logwarn("%2d <-     %s %"NVff"s excl = %"NVff"s incl - %"NVff"s (%"NVff"-%"NVff"), oh %"NVff"-%"NVff"=%"NVff"t, d%d @%d:%d #%lu %p\n",
            subr_entry->subr_prof_depth,
            called_subname_pv,
            excl_subr_sec, incl_subr_sec, called_sub_secs,
            cumulative_subr_secs, subr_entry->initial_subr_secs,
            cumulative_overhead_ticks, subr_entry->initial_overhead_ticks, overhead_ticks,
            (int)subr_entry->called_cv_depth,
            subr_entry->caller_fid, subr_entry->caller_line,
            subr_entry->subr_call_seqn, (void*)subr_entry);

    /* only count inclusive time for the outer-most calls */
    if (subr_entry->called_cv_depth <= 1) {
        incl_time_sv = *av_fetch(subr_call_av, NYTP_SCi_INCL_RTIME, 1);
        sv_setnv(incl_time_sv, SvNV(incl_time_sv)+incl_subr_sec);
    }
    else {
        /* recursing into an already entered sub */
        /* measure max depth and accumulate incl time separately */
        SV *reci_time_sv = *av_fetch(subr_call_av, NYTP_SCi_RECI_RTIME, 1);
        SV *max_depth_sv = *av_fetch(subr_call_av, NYTP_SCi_REC_DEPTH, 1);
        sv_setnv(reci_time_sv, (SvOK(reci_time_sv)) ? SvNV(reci_time_sv)+incl_subr_sec : incl_subr_sec);
        /* we track recursion depth here, which is called_cv_depth-1 */
        if (!SvOK(max_depth_sv) || subr_entry->called_cv_depth-1 > SvIV(max_depth_sv))
            sv_setiv(max_depth_sv, subr_entry->called_cv_depth-1);
    }
    excl_time_sv = *av_fetch(subr_call_av, NYTP_SCi_EXCL_RTIME, 1);
    sv_setnv(excl_time_sv, SvNV(excl_time_sv)+excl_subr_sec);

    subr_entry_destroy(aTHX_ subr_entry);

    cumulative_subr_secs += excl_subr_sec;
    SETERRNO(saved_errno, 0);
}

static void         /* wrapper called at scope exit due to save_destructor below */
incr_sub_inclusive_time_ix(pTHX_ void *subr_entry_ix_void)
{
    /* recover the I32 ix that was stored as a void pointer */
    I32 save_ix = (I32)PTR2IV(subr_entry_ix_void);
    incr_sub_inclusive_time(aTHX_ subr_entry_ix_ptr(save_ix));
}


static CV *
resolve_sub_to_cv(pTHX_ SV *sv, GV **subname_gv_ptr)
{
    GV *dummy_gv;
    HV *stash;
    CV *cv;

    if (!subname_gv_ptr)
        subname_gv_ptr = &dummy_gv;
    else
        *subname_gv_ptr = Nullgv;

    /* copied from top of perl's pp_entersub */
    /* modified to return either CV or else a GV */
    /* or a NULL in cases that pp_entersub would croak */
    switch (SvTYPE(sv)) {
        default:
            if (!SvROK(sv)) {
                char *sym;

                if (sv == &PL_sv_yes) {           /* unfound import, ignore */
                    return NULL;
                }
                if (SvGMAGICAL(sv)) {
                    mg_get(sv);
                    if (SvROK(sv))
                        goto got_rv;
                    sym = SvPOKp(sv) ? SvPVX(sv) : Nullch;
                }
                else
                    sym = SvPV_nolen(sv);
                if (!sym)
                    return NULL;
                if (PL_op->op_private & HINT_STRICT_REFS)
                    return NULL;
                cv = get_cv(sym, TRUE);
                break;
            }
            got_rv:
            {
                SV **sp = &sv;                    /* Used in tryAMAGICunDEREF macro. */
                tryAMAGICunDEREF(to_cv);
            }
            cv = (CV*)SvRV(sv);
            if (SvTYPE(cv) == SVt_PVCV)
                break;
            /* FALL THROUGH */
        case SVt_PVHV:
        case SVt_PVAV:
            return NULL;
        case SVt_PVCV:
            cv = (CV*)sv;
            break;
        case SVt_PVGV:
            if (!(isGV_with_GP(sv) && (cv = GvCVu((GV*)sv))))
                cv = sv_2cv(sv, &stash, subname_gv_ptr, FALSE);
            if (!cv)                              /* would autoload in this situation */
                return NULL;
            break;
    }
    if (cv && !*subname_gv_ptr && CvGV(cv) && isGV_with_GP(CvGV(cv))) {
        *subname_gv_ptr = CvGV(cv);
    }
    return cv;
}



static CV*
current_cv(pTHX_ I32 ix, PERL_SI *si)
{
    /* returning the current cv */
    /* logic based on perl's S_deb_curcv in dump.c */
    /* see also http://search.cpan.org/dist/Devel-StackBlech/ */
    PERL_CONTEXT *cx;
    if (!si)
        si = PL_curstackinfo;

    if (ix < 0) {
        /* caller isn't on the same stack so we'll walk the stacks as well */
        if (si->si_type != PERLSI_MAIN)
            return current_cv(aTHX_ si->si_prev->si_cxix, si->si_prev);
        if (trace_level >= 9)
            logwarn("finding current_cv(%d,%p) si_type %d - context stack empty\n",
                (int)ix, (void*)si, (int)si->si_type);
        return Nullcv;  /* PL_main_cv ? */
    }

    cx = &si->si_cxstack[ix];

    if (trace_level >= 9)
        logwarn("finding current_cv(%d,%p) - cx_type %d %s, si_type %d\n",
            (int)ix, (void*)si, CxTYPE(cx), cx_block_type(cx), (int)si->si_type);

    /* the common case of finding the caller on the same stack */
    if (CxTYPE(cx) == CXt_SUB || CxTYPE(cx) == CXt_FORMAT)
        return cx->blk_sub.cv;
    else if (CxTYPE(cx) == CXt_EVAL && !CxTRYBLOCK(cx))
        return current_cv(aTHX_ ix - 1, si); /* recurse up stack */
    else if (ix == 0 && si->si_type == PERLSI_MAIN)
        return PL_main_cv;
    else if (ix > 0)                         /* more on this stack? */
        return current_cv(aTHX_ ix - 1, si); /* recurse up stack */

    /* caller isn't on the same stack so we'll walk the stacks as well */
    if (si->si_type != PERLSI_MAIN) {
        return current_cv(aTHX_ si->si_prev->si_cxix, si->si_prev);
    }
    return Nullcv;
}


static I32
subr_entry_setup(pTHX_ COP *prev_cop, subr_entry_t *clone_subr_entry, OPCODE op_type, SV *subr_sv)
{
    int saved_errno = errno;
    subr_entry_t *subr_entry;
    I32 prev_subr_entry_ix;
    subr_entry_t *caller_subr_entry;
    const char *found_caller_by;
    char *file;

    /* allocate struct to save stack (very efficient) */
    /* XXX "warning: cast from pointer to integer of different size" with use64bitall=define */
    prev_subr_entry_ix = subr_entry_ix;
    subr_entry_ix = SSNEWa(sizeof(*subr_entry), MEM_ALIGNBYTES);

    if (subr_entry_ix <= prev_subr_entry_ix) {
        /* one cause of this is running NYTProf with threads */
        logwarn("NYTProf panic: stack is confused, giving up!\n");
        /* limit the damage */
        disable_profile(aTHX);
        return prev_subr_entry_ix;
    }

    subr_entry = subr_entry_ix_ptr(subr_entry_ix);
    Zero(subr_entry, 1, subr_entry_t);

    subr_entry->prev_subr_entry_ix = prev_subr_entry_ix;
    caller_subr_entry = subr_entry_ix_ptr(prev_subr_entry_ix);
    subr_entry->subr_prof_depth = (caller_subr_entry)
        ? caller_subr_entry->subr_prof_depth+1 : 1;

    if (profile_usecputime)
        times(&subr_entry->initial_call_cputimes);
    else
        get_time_of_day(subr_entry->initial_call_timeofday);
    subr_entry->initial_overhead_ticks = cumulative_overhead_ticks;
    subr_entry->initial_subr_secs      = cumulative_subr_secs;
    subr_entry->subr_call_seqn         = ++cumulative_subr_seqn;

    /* try to work out what sub's being called in advance
     * mainly for xsubs because otherwise they're transparent
     * because xsub calls don't get a new context
     */
    if (op_type == OP_ENTERSUB || op_type == OP_GOTO) {
        GV *called_gv = Nullgv;
        subr_entry->called_cv = resolve_sub_to_cv(aTHX_ subr_sv, &called_gv);
        if (called_gv) {
            subr_entry->called_subpkg_pv = HvNAME(GvSTASH(called_gv));
            subr_entry->called_subnam_sv = newSVpv(GvNAME(called_gv), 0);
        }
        else {
            subr_entry->called_subnam_sv = newSV(0); /* see incr_sub_inclusive_time */
        }
        subr_entry->called_is_xs = NULL; /* work it out later */
    }
    else { /* slowop */

        /* pretend slowops (builtins) are xsubs */
        const char *slowop_name = PL_op_name[op_type];
        if (profile_slowops == 1) { /* 1 == put slowops into 1 package */
            subr_entry->called_subpkg_pv = "CORE";
            subr_entry->called_subnam_sv = newSVpv(slowop_name, 0);
        }
        else {                     /* 2 == put slowops into multiple packages */
            SV **opname = NULL;
            SV *sv;
            if (!slowop_name_cache)
                slowop_name_cache = newAV();
            opname = av_fetch(slowop_name_cache, op_type, TRUE);
            if (!opname)
                croak("panic: opname cache read for '%s' (%d)\n", slowop_name, op_type);
            sv = *opname;

            if(!SvOK(sv)) {
                const STRLEN len = strlen(slowop_name);
                sv_grow(sv, 5 + len + 1);
                memcpy(SvPVX(sv), "CORE:", 5);
                memcpy(SvPVX(sv) + 5, slowop_name, len + 1);
                SvCUR_set(sv, 5 + len);
                SvPOK_on(sv);
            }
            subr_entry->called_subnam_sv = SvREFCNT_inc(sv);
            subr_entry->called_subpkg_pv = CopSTASHPV(PL_curcop);
        }
        subr_entry->called_cv_depth = 1; /* an approximation for slowops */
        subr_entry->called_is_xs = "sop";
    }

    /* These refer to the last perl statement executed, so aren't
     * strictly correct where an opcode or xsub is making the call,
     * but they're still more useful than nothing.
     * In reports the references line shows calls made by the
     * opcode or xsub that's called at that line.
     */
    file = OutCopFILE(prev_cop);
    subr_entry->caller_fid = (file == last_executed_fileptr)
        ? last_executed_fid
        : get_file_id(aTHX_ file, strlen(file), NYTP_FIDf_VIA_SUB);
    subr_entry->caller_line = CopLINE(prev_cop);

    /* Gather details about the calling subroutine */
    if (clone_subr_entry) {
        subr_entry->caller_subpkg_pv = clone_subr_entry->caller_subpkg_pv;
        subr_entry->caller_subnam_sv = SvREFCNT_inc(clone_subr_entry->caller_subnam_sv);
        found_caller_by = "(cloned)";
    }
    else
    /* Should we calculate the caller or can we reuse the caller_subr_entry?
     * Sometimes we'll have a caller_subr_entry but it won't have the name yet.
     * For example if the caller is an xsub that's callback into perl.
     */
    if (profile_findcaller             /* user wants us to calculate each time */
    || !caller_subr_entry                     /* we don't have a caller struct */
    || !caller_subr_entry->called_subpkg_pv   /* we don't have caller details  */
    || !caller_subr_entry->called_subnam_sv
    || !SvOK(caller_subr_entry->called_subnam_sv)
    ) {

        /* get the current CV and determine the current sub name from that */
        CV *caller_cv = current_cv(aTHX_ cxstack_ix, NULL);
        subr_entry->caller_subnam_sv = newSV(0); /* XXX add cache/stack thing for these SVs */

        if (0) {
            logwarn(" .. caller_subr_entry %p(%s::%s) cxstack_ix=%d: caller_cv=%p\n",
                (void*)caller_subr_entry,
                caller_subr_entry ? caller_subr_entry->called_subpkg_pv : "(null)",
                (caller_subr_entry && caller_subr_entry->called_subnam_sv && SvOK(caller_subr_entry->called_subnam_sv))
                    ? SvPV_nolen(caller_subr_entry->called_subnam_sv) : "(null)",
                (int)cxstack_ix, (void*)caller_cv
            );
        }

        if (caller_cv == PL_main_cv) {
            /* PL_main_cv is run-time main (compile-time, eg 'use', is a main::BEGIN) */
            /* We don't record timing data for main::RUNTIME because timing data
             * is stored per calling location, and there is no calling location.
             * XXX Currently we don't output a subinfo for main::RUNTIME unless
             * some sub is called from main::RUNTIME. That may change.
             */
            subr_entry->caller_subpkg_pv = "main";
            sv_setpvs(subr_entry->caller_subnam_sv, "RUNTIME"); /* *cough* */
            ++main_runtime_used;
        }
        else if (caller_cv == 0) {
            /* should never happen - but does in PostgreSQL 8.4.1 plperl
             * possibly because perl_run() has already returned
             */
            subr_entry->caller_subpkg_pv = "main";
            sv_setpvs(subr_entry->caller_subnam_sv, "NULL"); /* *cough* */
        }
        else {
            HV *stash_hv = NULL;
            GV *gv = CvGV(caller_cv);
            GV *egv = GvEGV(gv);
            if (!egv)
                gv = egv;

            if (gv && (stash_hv = GvSTASH(gv))) {
                subr_entry->caller_subpkg_pv = HvNAME(stash_hv);
                sv_setpvn(subr_entry->caller_subnam_sv,GvNAME(gv),GvNAMELEN(gv));
            }
            else {
                logwarn("Can't determine name of calling sub (GV %p, Stash %p, CV flags %d) at %s line %d\n",
                    (void*)gv, (void*)stash_hv, (int)CvFLAGS(caller_cv),
                    OutCopFILE(prev_cop), (int)CopLINE(prev_cop));
                sv_dump((SV*)caller_cv);

                subr_entry->caller_subpkg_pv = "__UNKNOWN__";
                sv_setpvs(subr_entry->caller_subnam_sv, "__UNKNOWN__");
            }
        }
        found_caller_by = (profile_findcaller) ? "" : "(calculated)";
    }
    else {
        subr_entry_t *caller_se = caller_subr_entry;
        int caller_is_op = caller_se->called_is_xs && strEQ(caller_se->called_is_xs,"sop");
        /* if the caller is an op then use the caller of that op as our caller.
         * that makes more sense from the users perspective (and is consistent
         * with the findcaller=1 option).
         * XXX disabled for now because (I'm pretty sure) it needs a corresponding
         * change in incr_sub_inclusive_time otherwise the incl/excl times are distorted.
         */
        if (0 && caller_is_op) {
            subr_entry->caller_subpkg_pv = caller_se->caller_subpkg_pv;
            subr_entry->caller_subnam_sv = SvREFCNT_inc(caller_se->caller_subnam_sv);
        }
        else {
            subr_entry->caller_subpkg_pv = caller_se->called_subpkg_pv;
            subr_entry->caller_subnam_sv = SvREFCNT_inc(caller_se->called_subnam_sv);
        }
        found_caller_by = "(inherited)";
    }

    if (trace_level >= 4) {
        logwarn("%2d >> %s at %u:%d from %s::%s %s %s\n",
            subr_entry->subr_prof_depth,
            PL_op_name[op_type],
            subr_entry->caller_fid, subr_entry->caller_line,
            subr_entry->caller_subpkg_pv,
            SvPV_nolen(subr_entry->caller_subnam_sv),
            found_caller_by,
            subr_entry_summary(aTHX_ subr_entry, 0)
        );
    }

    /* This is our safety-net destructor. For perl subs an identical destructor
     * will be pushed onto the stack _inside_ the scope we're interested in.
     * That destructor will be more accurate than this one. This one is here
     * mainly to catch exceptions thrown from xs subs and slowops.
     */
    save_destructor_x(incr_sub_inclusive_time_ix, INT2PTR(void *, (IV)subr_entry_ix));

    SETERRNO(saved_errno, 0);

    return subr_entry_ix;
}


static OP *
pp_entersub_profiler(pTHX)
{
    return pp_subcall_profiler(aTHX_ 0);
}

static OP *
pp_slowop_profiler(pTHX)
{
    return pp_subcall_profiler(aTHX_ 1);
}

static OP *
pp_subcall_profiler(pTHX_ int is_slowop)
{
    int saved_errno = errno;
    OP *op;
    COP *prev_cop = PL_curcop;                    /* not PL_curcop_nytprof here */
    OP *next_op = PL_op->op_next;                 /* op to execute after sub returns */
    /* pp_entersub can be called with PL_op->op_type==0 */
    OPCODE op_type = (is_slowop || (opcode) PL_op->op_type == OP_GOTO) ? (opcode) PL_op->op_type : OP_ENTERSUB;

    CV *called_cv;
    dSP;
    SV *sub_sv = *SP;
    I32 this_subr_entry_ix = 0; /* local copy (needed for goto) */

    subr_entry_t *subr_entry;

    /* pre-conditions */
    if (!profile_subs   /* not profiling subs */
        /* don't profile if currently disabled */
    ||  !is_profiling
        /* don't profile calls to non-existant import() methods */
        /* or our DB::_INIT as that makes tests perl version sensitive */
    || (op_type==OP_ENTERSUB && (sub_sv == &PL_sv_yes || sub_sv == DB_INIT_cv || sub_sv == DB_fin_cv))
        /* don't profile other kinds of goto */
    || (op_type==OP_GOTO &&
        (  !(SvROK(sub_sv) && SvTYPE(SvRV(sub_sv)) == SVt_PVCV)
        || !subr_entry_ix ) /* goto out of sub whose entry wasn't profiled */
       )
#ifdef MULTIPLICITY
    || (my_perl != orig_my_perl)
#endif
    ) {
        return run_original_op(op_type);
    }

    if (!profile_stmts)
        reinit_if_forked(aTHX);

    if (trace_level >= 99) {
        logwarn("profiling a call [op %ld, %s, seix %d]\n",
            (long)op_type, PL_op_name[op_type], (int)subr_entry_ix);
        /* crude, but the only way to deal with the miriad logic at the
         * start of pp_entersub (which ought to be available as separate sub)
         */
        sv_dump(sub_sv);
    }
    

    /* Life would be so much simpler if we could reliably tell, at this point,
     * what sub was going to get called. But we can't in many cases.
     * So we gather up as much into as possible before the call.
     */

    if (op_type != OP_GOTO) {

        /* For normal subs, pp_entersub enters the sub and returns the
         * first op *within* the sub (typically a nextstate/dbstate).
         * For XS subs, pp_entersub executes the entire sub
         * and returns the op *after* the sub (PL_op->op_next).
         * Other ops we profile (eg slowops) act like xsubs.
         */

        called_cv = NULL;
        this_subr_entry_ix = subr_entry_setup(aTHX_ prev_cop, NULL, op_type, sub_sv);

        /* This call may exit via an exception, in which case the
        * remaining code below doesn't get executed and the sub call
        * details are discarded. For perl subs that just means we don't
        * see calls the failed with "Unknown sub" errors, etc.
        * For xsubs it's a more significant issue. Especially if the
        * xsub calls back into perl.
        */
        SETERRNO(saved_errno, 0);
        op = run_original_op(op_type);
        saved_errno = errno;

    }
    else {

        /* goto &sub opcode acts like a return followed by a call all in one.
         * When this op starts executing, the 'current' subr_entry that was
         * pushed onto the savestack by pp_subcall_profiler will be 'already_counted'
         * so the profiling of that call will be handled naturally for us.
         * So far so good.
         * Before it gets destroyed we'll take a copy of the subr_entry.
         * Then tell subr_entry_setup() to use our copy as a template so it'll
         * seem like the sub we goto'd was called by the same sub that called
         * the one that executed the goto. Except that we do use the fid:line
         * of the goto statement. That way the call graph makes sense and the
         * 'calling location' make sense. Got all that?
         */
        /* save a copy of prev_cop - see t/test18-goto2.p */
        COP prev_cop_copy = *prev_cop;
        /* save a copy of the subr_entry of the sub we're goto'ing out of */
        /* so we can reuse the caller _* info after it's destroyed */
        subr_entry_t goto_subr_entry;
        subr_entry_t *src = subr_entry_ix_ptr(subr_entry_ix);
        Copy(src, &goto_subr_entry, 1, subr_entry_t);

        /* XXX if the goto op or goto'd xsub croaks then this'll leak */
        /* we can't mortalize here because we're about to leave scope */
        SvREFCNT_inc(goto_subr_entry.caller_subnam_sv);
        SvREFCNT_inc(goto_subr_entry.called_subnam_sv);
        SvREFCNT_inc(sub_sv);

        /* grab the CvSTART of the called sub since it's available */
        called_cv = (CV*)SvRV(sub_sv);

        /* if goto &sub  then op will be the first op of the called sub
         * if goto &xsub then op will be the first op after the call to the
         * op we're goto'ing out of.
         */
        SETERRNO(saved_errno, 0);
        op = run_original_op(op_type);  /* perform the goto &sub */
        saved_errno = errno;

        /* now we're in goto'd sub, mortalize the REFCNT_inc's done above */
        sv_2mortal(goto_subr_entry.caller_subnam_sv);
        sv_2mortal(goto_subr_entry.called_subnam_sv);
        this_subr_entry_ix = subr_entry_setup(aTHX_ &prev_cop_copy, &goto_subr_entry, op_type, sub_sv);
        SvREFCNT_dec(sub_sv);
    }

    subr_entry = subr_entry_ix_ptr(this_subr_entry_ix);

    /* detect wierdness/corruption */
    assert(subr_entry->caller_fid < next_fid);

    /* Check if this call has already been counted because the op performed
     * a leave_scope(). E.g., OP_SUBSTCONT at end of s/.../\1/
     * or Scope::Upper's unwind()
     */
    if (subr_entry->already_counted) {
        if (trace_level >= 9)
            logwarn("%2d --     %s::%s already counted %s\n",
                subr_entry->subr_prof_depth,
                subr_entry->called_subpkg_pv,
                (subr_entry->called_subnam_sv && SvOK(subr_entry->called_subnam_sv))
                    ? SvPV_nolen(subr_entry->called_subnam_sv)
                    : "?",
                subr_entry_summary(aTHX_ subr_entry, 1));
        assert(subr_entry->already_counted < 3);
        goto skip_sub_profile;
    }

    if (is_slowop) {
        /* already fully handled by subr_entry_setup */
    }
    else {
        char *stash_name = NULL;
        const char *is_xs = NULL;

        if (op_type == OP_GOTO) {
            /* use the called_cv that was the arg to the goto op */
            is_xs = (CvISXSUB(called_cv)) ? "xsub" : NULL;
        }
        else
        if (op != next_op) {   /* have entered a sub */
            /* use cv of sub we've just entered to get name */
            called_cv = cxstack[cxstack_ix].blk_sub.cv;
            is_xs = NULL;
        }
        else {                 /* have returned from XS so use sub_sv for name */
            /* determine the original fully qualified name for sub */
            /* CV or NULL */
            GV *gv = NULL;
            called_cv = resolve_sub_to_cv(aTHX_ sub_sv, &gv);
            
            if (!called_cv && gv) { /* XXX no test case  for this */
                stash_name = HvNAME(GvSTASH(gv));
                sv_setpv(subr_entry->called_subnam_sv, GvNAME(gv));
                if (trace_level >= 0)
                    logwarn("Assuming called sub is named %s::%s at %s line %d (please report as a bug)\n",
                        stash_name, SvPV_nolen(subr_entry->called_subnam_sv),
                        OutCopFILE(prev_cop), (int)CopLINE(prev_cop));
            }
            is_xs = "xsub";
        }

        if (called_cv && CvGV(called_cv)) {
            GV *gv = CvGV(called_cv);
            /* Class::MOP can create CvGV where SvTYPE of GV is SVt_NULL */
            if (SvTYPE(gv) == SVt_PVGV && GvSTASH(gv)) {
                /* for a plain call of an imported sub the GV is of the current
                * package, so we dig to find the original package
                */
                stash_name = HvNAME(GvSTASH(gv));
                sv_setpv(subr_entry->called_subnam_sv, GvNAME(gv));
            }
            else if (trace_level >= 1) {
                logwarn("NYTProf is confused about CV %p called as %s at %s line %d (please report as a bug)\n",
                    (void*)called_cv, SvPV_nolen(sub_sv), OutCopFILE(prev_cop), (int)CopLINE(prev_cop));
                /* looks like Class::MOP doesn't give the CV GV stash a name */
                if (trace_level >= 2)
                    sv_dump((SV*)called_cv); /* coredumps in Perl_do_gvgv_dump, looks line GvXPVGV is false, presumably on a Class::MOP wierdo sub */
            }
        }

        /* called_subnam_sv should have been set by now - else we're getting desperate */
        if (!SvOK(subr_entry->called_subnam_sv)) {
            const char *what = (is_xs) ? is_xs : "sub";

            if (!called_cv) { /* should never get here as pp_entersub would have croaked */
                logwarn("unknown entersub %s '%s' (please report this as a bug)\n", what, SvPV_nolen(sub_sv));
                stash_name = CopSTASHPV(PL_curcop);
                sv_setpvf(subr_entry->called_subnam_sv, "__UNKNOWN__[%s,%s])", what, SvPV_nolen(sub_sv));
            }
            else { /* unnamed CV, e.g. seen in mod_perl/Class::MOP. XXX do better? */
                stash_name = HvNAME(CvSTASH(called_cv));
                sv_setpvf(subr_entry->called_subnam_sv, "__UNKNOWN__[%s,0x%p]", what, (void*)called_cv);
                if (trace_level)
                    logwarn("unknown entersub %s assumed to be anon called_cv '%s'\n",
                        what, SvPV_nolen(sub_sv));
            }
            if (trace_level >= 9)
                sv_dump(sub_sv);
        }
        
        subr_entry->called_subpkg_pv = stash_name;
        if (*SvPVX(subr_entry->called_subnam_sv) == 'B')
            append_linenum_to_begin(aTHX_ subr_entry);

        /* if called was xsub then we've already left it, so use depth+1 */
        subr_entry->called_cv_depth = (called_cv) ? CvDEPTH(called_cv)+(is_xs?1:0) : 0;
        subr_entry->called_cv = called_cv;
        subr_entry->called_is_xs = is_xs;
    }

    /* ignore our own DB::_INIT sub - only shows up with 5.8.9+ & 5.10.1+ */
    if (subr_entry->called_is_xs
    && subr_entry->called_subpkg_pv[0] == 'D'
    && subr_entry->called_subpkg_pv[1] == 'B'
    && subr_entry->called_subpkg_pv[2] == '\0'
    ) {
        STRLEN len;
        char *p = SvPV(subr_entry->called_subnam_sv, len);

        if(memEQs(p, len, "_INIT")) {
            subr_entry->already_counted++;
            goto skip_sub_profile;
        }
    }
    /* catch profile_subs being turned off by disable_profile call */
    if (!profile_subs)
        subr_entry->already_counted++;

    if (trace_level >= 3) {
        logwarn("%2d ->%4s %s::%s from %s::%s @%u:%u (d%d, oh %"NVff"t, sub %"NVff"s) #%lu\n",
            subr_entry->subr_prof_depth,
            (subr_entry->called_is_xs) ? subr_entry->called_is_xs : "sub",
            subr_entry->called_subpkg_pv,
            subr_entry->called_subnam_sv ? SvPV_nolen(subr_entry->called_subnam_sv) : "(null)",
            subr_entry->caller_subpkg_pv,
            subr_entry->caller_subnam_sv ? SvPV_nolen(subr_entry->caller_subnam_sv) : "(null)",
            subr_entry->caller_fid, subr_entry->caller_line,
            subr_entry->called_cv_depth,
            subr_entry->initial_overhead_ticks,
            subr_entry->initial_subr_secs,
            subr_entry->subr_call_seqn
        );
    }

    if (subr_entry->called_is_xs) {
        /* for xsubs/builtins we've already left the sub, so end the timing now
         * rather than wait for the calling scope to get cleaned up.
         */
        incr_sub_inclusive_time(aTHX_ subr_entry);
    }
    else {
        /* push a destructor hook onto the context stack to ensure we account
         * for time in the sub when we leave it, even if via an exception.
         */
        save_destructor_x(incr_sub_inclusive_time_ix, INT2PTR(void *, (IV)this_subr_entry_ix));
    }

    skip_sub_profile:
    SETERRNO(saved_errno, 0);

    return op;
}


static OP *
pp_stmt_profiler(pTHX)                            /* handles OP_DBSTATE, OP_SETSTATE, etc */
{
    OP *op = run_original_op(PL_op->op_type);
    DB_stmt(aTHX_ NULL, op);
    return op;
}

static OP *
pp_leave_profiler(pTHX)                           /* handles OP_LEAVESUB, OP_LEAVEEVAL, etc */
{
    OP *op = run_original_op(PL_op->op_type);
    DB_leave(aTHX_ op);
    return op;
}

static OP *
pp_fork_profiler(pTHX)                            /* handles OP_FORK */
{
    OP *op = run_original_op(PL_op->op_type);
    reinit_if_forked(aTHX);
    return op;
}

static OP *
pp_exit_profiler(pTHX)                            /* handles OP_EXIT, OP_EXEC, etc */
{
    DB_leave(aTHX_ NULL);                         /* call DB_leave *before* run_original_op() */
    if (PL_op->op_type == OP_EXEC)
        finish_profile(aTHX);                     /* this is the last chance we'll get */
    return run_original_op(PL_op->op_type);
}


static int
enable_profile(pTHX_ char *file)
{
    /* enable the run-time aspects to profiling */
    int prev_is_profiling = is_profiling;
#ifdef MULTIPLICITY
    if (my_perl != orig_my_perl)
        return 0;
#endif

    if (trace_level)
        logwarn("~ enable_profile (previously %s) to %s\n",
            prev_is_profiling ? "enabled" : "disabled",
            (file && *file) ? file : PROF_output_file);

    reinit_if_forked(aTHX);

    if (file && *file && strNE(file, PROF_output_file)) {
        /* caller wants output to go to a new file */
        close_output_file(aTHX);
        strncpy(PROF_output_file, file, sizeof(PROF_output_file)-1);
    }

    if (!out) {
        open_output_file(aTHX_ PROF_output_file);
    }

    last_executed_fileptr = NULL;   /* discard cached OutCopFILE   */
    is_profiling = 1;               /* enable NYTProf profilers    */
    if (opt_use_db_sub)             /* set PL_DBsingle if required */
        sv_setiv(PL_DBsingle, 1);

    /* discard time spent since profiler was disabled */
    if (profile_usecputime) {
        times(&start_ctime);
    }
    else {
        get_time_of_day(start_time);
    }

    return prev_is_profiling;
}


static int
disable_profile(pTHX)
{
    int prev_is_profiling = is_profiling;
#ifdef MULTIPLICITY
    if (my_perl != orig_my_perl)
        return 0;
#endif
    if (is_profiling) {
        if (opt_use_db_sub)
            sv_setiv(PL_DBsingle, 0);
        if (out)
            NYTP_flush(out);
        is_profiling = 0;
    }
    if (trace_level)
        logwarn("~ disable_profile (previously %s, pid %d)\n",
            prev_is_profiling ? "enabled" : "disabled", getpid());
    return prev_is_profiling;
}


static void
finish_profile(pTHX)
{
    int saved_errno = errno;
#ifdef MULTIPLICITY
    if (my_perl != orig_my_perl)
        return;
#endif

    if (trace_level >= 1)
        logwarn("~ finish_profile (overhead %"NVff"s, is_profiling %d)\n",
            cumulative_overhead_ticks/ticks_per_sec, is_profiling);

    /* write data for final statement, unless DB_leave has already */
    if (!profile_leave || opt_use_db_sub)
        DB_stmt(aTHX_ NULL, NULL);

    disable_profile(aTHX);

    close_output_file(aTHX);

    /* reset sub profiler data  */
    hv_clear(sub_callers_hv);
    /* reset other state */
    cumulative_overhead_ticks = 0;
    cumulative_subr_secs = 0;

    SETERRNO(saved_errno, 0);
}


/* Initial setup - should only be called once */
static int
init_profiler(pTHX)
{
#ifndef HAS_GETTIMEOFDAY
    SV **svp;
#endif

#ifdef MULTIPLICITY
    if (!orig_my_perl)
        orig_my_perl = my_perl;
    else if (orig_my_perl != my_perl) {
        logwarn("NYTProf: threads/multiplicity not supported!\n");
        return 0;
    }
#endif

    /* Save the process id early. We monitor it to detect forks */
    last_pid = getpid();
    ticks_per_sec = (profile_usecputime) ? PL_clocktick : CLOCKS_PER_TICK;
    DB_INIT_cv = (SV*)GvCV(gv_fetchpv("DB::_INIT",          FALSE, SVt_PVCV));
    DB_fin_cv  = (SV*)GvCV(gv_fetchpv("DB::finish_profile", FALSE, SVt_PVCV));

    if (opt_use_db_sub) {
        PL_perldb |= PERLDBf_LINE;    /* line-by-line profiling via DB::DB (if $DB::single true) */
        PL_perldb |= PERLDBf_SINGLE; /* start (after BEGINs) with single-step on XXX still needed? */
    }

    if (profile_opts & NYTP_OPTf_OPTIMIZE)
         PL_perldb &= ~PERLDBf_NOOPT;
    else PL_perldb |=  PERLDBf_NOOPT;

    if (profile_opts & NYTP_OPTf_SAVESRC) {
        /* ask perl to keep the source lines so we can copy them */
        PL_perldb |= PERLDBf_SAVESRC | PERLDBf_SAVESRC_NOSUBS;
    }

    if (!opt_nameevals)
        PL_perldb &= PERLDBf_NAMEEVAL;
    if (!opt_nameanonsubs)
        PL_perldb &= PERLDBf_NAMEANON;

    if (opt_perldb) /* force a PL_perldb value - for testing only, not documented */
        PL_perldb = opt_perldb;

#ifdef HAS_CLOCK_GETTIME
    if (profile_clock == -1) { /* auto select */
#  ifdef CLOCK_MONOTONIC
        profile_clock = CLOCK_MONOTONIC;
#  else
        profile_clock = CLOCK_REALTIME;
#  endif
    }
    /* downgrade to CLOCK_REALTIME if desired clock not available */
    if (clock_gettime(profile_clock, &start_time) != 0) {
        if (trace_level)
            logwarn("~ clock_gettime clock %d not available (%s) using CLOCK_REALTIME instead\n",
                profile_clock, strerror(errno));
        profile_clock = CLOCK_REALTIME;
        /* check CLOCK_REALTIME as well, just in case */
        if (clock_gettime(profile_clock, &start_time) != 0)
            croak("clock_gettime CLOCK_REALTIME not available (%s), aborting",
                strerror(errno));
    }
#else
    if (profile_clock != -1) {  /* user tried to select different clock */
        logwarn("clock %d not available (clock_gettime not supported on this system)\n", profile_clock);
        profile_clock = -1;
    }
#endif

    if (trace_level)
        logwarn("~ init_profiler for pid %d, clock %d, start %d, perldb 0x%lx\n",
            last_pid, profile_clock, profile_start, (long unsigned)PL_perldb);

    if (get_hv("DB::sub", 0) == NULL) {
        logwarn("NYTProf internal error - perl not in debug mode\n");
        return 0;
    }

#ifndef HAS_GETTIMEOFDAY
    require_pv("Time/HiRes.pm");                  /* before opcode redirection */
    svp = hv_fetch(PL_modglobal, "Time::U2time", 12, 0);
    if (!svp || !SvIOK(*svp)) croak("Time::HiRes is required");
    u2time = INT2PTR(int(*)(pTHX_ UV*), SvIV(*svp));
    if (trace_level)
        logwarn("NYTProf using Time::HiRes %p\n", u2time);
#endif

    /* create file id mapping hash */
    hashtable.table = (Hash_entry**)safemalloc(sizeof(Hash_entry*) * hashtable.size);
    memset(hashtable.table, 0, sizeof(Hash_entry*) * hashtable.size);

    open_output_file(aTHX_ PROF_output_file);

    /* redirect opcodes for statement profiling */
    Newxc(PL_ppaddr_orig, OP_max, void *, orig_ppaddr_t);
    Copy(PL_ppaddr, PL_ppaddr_orig, OP_max, void *);
    if (profile_stmts && !opt_use_db_sub) {
        PL_ppaddr[OP_NEXTSTATE]  = pp_stmt_profiler;
        PL_ppaddr[OP_DBSTATE]    = pp_stmt_profiler;
#ifdef OP_SETSTATE
        PL_ppaddr[OP_SETSTATE]   = pp_stmt_profiler;
#endif
        if (profile_leave) {
            PL_ppaddr[OP_LEAVESUB]   = pp_leave_profiler;
            PL_ppaddr[OP_LEAVESUBLV] = pp_leave_profiler;
            PL_ppaddr[OP_LEAVE]      = pp_leave_profiler;
            PL_ppaddr[OP_LEAVELOOP]  = pp_leave_profiler;
            PL_ppaddr[OP_LEAVEWRITE] = pp_leave_profiler;
            PL_ppaddr[OP_LEAVEEVAL]  = pp_leave_profiler;
            PL_ppaddr[OP_LEAVETRY]   = pp_leave_profiler;
            PL_ppaddr[OP_RETURN]     = pp_leave_profiler;
            /* natural end of simple loop */
            PL_ppaddr[OP_UNSTACK]    = pp_leave_profiler;
            /* OP_NEXT is missing because that jumps to OP_UNSTACK */
            /* OP_EXIT and OP_EXEC need special handling */
            PL_ppaddr[OP_EXIT]       = pp_exit_profiler;
            PL_ppaddr[OP_EXEC]       = pp_exit_profiler;
        }
    }
    /* calls reinit_if_forked() asap after a fork */
    PL_ppaddr[OP_FORK] = pp_fork_profiler;

    if (profile_slowops) {
        /* XXX this should turn into a loop over an array that maps
         * opcodes to the subname we'll use: OP_PRTF => "printf"
         */
#include "slowops.h"
    }

    /* redirect opcodes for caller tracking */
    if (!sub_callers_hv)
        sub_callers_hv = newHV();
    if (!pkg_fids_hv)
        pkg_fids_hv = newHV();
    PL_ppaddr[OP_ENTERSUB] = pp_entersub_profiler;
    PL_ppaddr[OP_GOTO]     = pp_entersub_profiler;

    if (!PL_checkav) PL_checkav = newAV();
    if (!PL_initav)  PL_initav  = newAV();
    if (!PL_endav)   PL_endav   = newAV();
    if (profile_start == NYTP_START_BEGIN) {
        enable_profile(aTHX_ NULL);
    }
    /* else handled by _INIT */
    /* defer some init until INIT phase */
    av_push(PL_initav, SvREFCNT_inc(get_cv("DB::_INIT", GV_ADDWARN)));

    /* seed first run time */
    if (profile_usecputime) {
        times(&start_ctime);
    }
    else {
        get_time_of_day(start_time);
    }

    if (trace_level >= 2)
        logwarn("~ init_profiler done\n");

    return 1;
}


/************************************
 * Devel::NYTProf::Reader Functions *
 ************************************/

static void
add_entry(pTHX_ AV *dest_av, unsigned int file_num, unsigned int line_num,
NV time, unsigned int eval_file_num, unsigned int eval_line_num, int count)
{
    /* get ref to array of per-line data */
    unsigned int fid = (eval_line_num) ? eval_file_num : file_num;
    SV *line_time_rvav = *av_fetch(dest_av, fid, 1);

    if (!SvROK(line_time_rvav))                   /* autoviv */
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
        if (!SvROK(eval_line_time_rvav))          /* autoviv */
            sv_setsv(eval_line_time_rvav, newRV_noinc((SV*)newAV()));

        store_profile_line_entry(aTHX_ eval_line_time_rvav, line_num, time, count, fid);
    }
}


static AV *
store_profile_line_entry(pTHX_ SV *rvav, unsigned int line_num, NV time,
int count, unsigned int fid)
{
    SV *time_rvav = *av_fetch((AV*)SvRV(rvav), line_num, 1);
    AV *line_av;
    if (!SvROK(time_rvav)) {                      /* autoviv */
        line_av = newAV();
        sv_setsv(time_rvav, newRV_noinc((SV*)line_av));
        av_store(line_av, 0, newSVnv(time));
        av_store(line_av, 1, newSViv(count));
        /* if eval then   2  is used for lines within the string eval */
        if (embed_fid_line) {                     /* used to optimize reporting */
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
            (count == 1) ? sv_inc(sv) : sv_setiv(sv, (IV)time + SvIV(sv));
        }
    }
    return line_av;
}


/* Given a sub_name lookup the package name in pkg_fids_hv hash.
 * pp_subcall_profiler() creates undef entries for a package the
 * first time a sub in the package is called.
 * Return Nullsv if there's no package name or no correponding entry
 * else returns the SV.
 * write_sub_line_ranges() updates the SV with the filename associated
 * with the package, or at least its best guess.
 * As most callers get len via the hash API, they will have an I32, where
 * "negative" length signifies UTF-8. As we're only dealing with looking for
 * ASCII here, it doesn't matter to use which encoding sub_name is in, but it
 * reduces total code by doing the abs(len) in here.
 */
static SV *
sub_pkg_filename_sv(pTHX_ char *sub_name, I32 len)
{
    SV **svp;
    const char *delim = "::";
    /* find end of package name */
    char *colon = rninstr(sub_name, sub_name+(len > 0 ? len : -len), delim, delim+2);
    if (!colon || colon == sub_name)
        return Nullsv;   /* no :: delimiter */
    svp = hv_fetch(pkg_fids_hv, sub_name, (I32)(colon-sub_name), 0);
    if (!svp)
        return Nullsv;   /* not a package we've profiled sub calls into */
    return *svp;
}


static int
parse_DBsub_value(pTHX_ SV *sv, STRLEN *filename_len_p, UV *first_line_p, UV *last_line_p) {
    /* "filename:first-last" */
    char *filename = SvPV_nolen(sv);
    char *first = strrchr(filename, ':');
    char *last = (first) ? strchr(first, '-') : NULL;

    if (!first || !last || !grok_number(first+1, last-first-1, first_line_p))
        return 0;
    if (last_line_p)
        *last_line_p = atoi(++last);
    if (filename_len_p)
        *filename_len_p = first - filename;

    return 1;
}

/* Returns a pointer to the ')' after the digits in the (?:re_)?eval prefix.
   As the prefix length is known, this gives the length of the digits.  */

static char *
eval_prefix(char *filename, const char *prefix, STRLEN prefix_len) {
    if (memEQ(filename, prefix, prefix_len)
        && isdigit(filename[prefix_len])) {
        char *s = filename + prefix_len + 1;

        while (isdigit(*s))
            ++s;
        if (s[0] == ')' && s[1] == '[')
            return s;
    }
    return NULL;
}

static void
write_sub_line_ranges(pTHX)
{
    char *sub_name;
    I32 sub_name_len;
    SV *file_lines_sv;
    HV *hv = GvHV(PL_DBsub);
    unsigned int fid;

    if (trace_level >= 2)
        logwarn("~ writing sub line ranges\n");

    /* Skim through PL_DBsub hash to build a package to filename hash
     * by associating the package part of the sub_name in the key
     * with the filename part of the value.
     * but only for packages we already know we're interested in
     */
    hv_iterinit(hv);
    while (NULL != (file_lines_sv = hv_iternextsv(hv, &sub_name, &sub_name_len))) {
        STRLEN file_lines_len;
        char *filename = SvPV(file_lines_sv, file_lines_len);
        char *first;
        STRLEN filename_len;
        SV *pkg_filename_sv;

        /* This is a heuristic, and might not be robust, but it seems that
           it's possible to get problematically bogus entries in this hash.
           Specifically, setting the 'lvalue' attribute on an XS subroutine
           during a bootstrap can cause op.c to load attributes, and in turn
           cause a DynaLoader::BEGIN entry in %DB::sub associated with the
           .pm file of the XS sub's module, not DynaLoader. This has the result
           that if we try to associate XSUBs with filenames using %DB::sub,
           we can go very wrong.

           Fortunately all "wrong" entries so far spotted have a line range
           with a non-zero start, and a zero end. This cannot be legal, so we
           ignore those.
         */

        if (file_lines_len > 4
            && filename[file_lines_len - 2] == '-' && filename[file_lines_len - 1] == '0'
            && filename[file_lines_len - 4] != ':' && filename[file_lines_len - 3] != '0')
            continue;

        first = strrchr(filename, ':');
        filename_len = (first) ? first - filename : 0;

        /* skip filenames for generated evals /\A\((?:re_)?eval \d+\)\[.*]\z/
         */
        if (filename_len > 9 && filename[filename_len - 1] == ']'
            && (eval_prefix(filename, "(eval ", 6) ||
                eval_prefix(filename, "(re_eval ", 9)))
            continue;

        /* get sv for package-of-subname to filename mapping */
        pkg_filename_sv = sub_pkg_filename_sv(aTHX_ sub_name, sub_name_len);

        if (!pkg_filename_sv) /* we don't know package */
            continue;

        /* already got a filename for this package XXX should allow multiple */
        if (SvOK(pkg_filename_sv))
            continue;

        /* ignore if filename is empty (eg xs) */
        if (!filename_len) {
            if (trace_level >= 3)
                logwarn("Sub %.*s has no filename associated (%s)\n",
                    (int)sub_name_len, sub_name, filename);
            continue;
        }

        /* associate the filename with the package */
        sv_setpvn(pkg_filename_sv, filename, filename_len);

        /* ensure a fid is assigned since we don't allow it below */
        fid = get_file_id(aTHX_ filename, filename_len, NYTP_FIDf_VIA_SUB);

        if (trace_level >= 3)
            logwarn("Associating package of %s with %.*s (fid %d)\n",
                 sub_name, (int)filename_len, filename, fid );
    }

    if (main_runtime_used) { /* Create fake entry for main::RUNTIME sub */
        char runtime[] = "main::RUNTIME";
        const I32 runtime_len = sizeof(runtime) - 1;
        SV *sv = *hv_fetch(hv, runtime, runtime_len, 1);

        /* get name of file that contained first profiled sub in 'main::' */
        SV *pkg_filename_sv = sub_pkg_filename_sv(aTHX_ runtime, runtime_len);
        if (!pkg_filename_sv) { /* no subs in main, so guess */
            sv_setpvn(sv, hashtable.first_inserted->key, hashtable.first_inserted->key_len);
        }
        else if (SvOK(pkg_filename_sv)) {
            sv_setsv(sv, pkg_filename_sv);
        }
        else {
            sv_setpvn(sv, "", 0);
        }
        sv_catpvs(sv, ":1-1");
    }

    /* Iterate over PL_DBsub writing out fid and source line range of subs.
     * If filename is missing (i.e., because it's an xsub so has no source file)
     * then use the filename of another sub in the same package.
     */
    while (NULL != (file_lines_sv = hv_iternextsv(hv, &sub_name, &sub_name_len))) {
        /* "filename:first-last" */
        char *filename = SvPV_nolen(file_lines_sv);
        STRLEN filename_len;
        UV first_line, last_line;

        if (!parse_DBsub_value(aTHX_ file_lines_sv, &filename_len, &first_line, &last_line)) {
            logwarn("Can't parse %%DB::sub entry for %s '%s'\n", sub_name, filename);
            continue;
        }

        if (!filename_len) {    /* no filename, so presumably a fake entry for xsub */
            /* do we know a filename that contains subs in the same package */
            SV *pkg_filename_sv = sub_pkg_filename_sv(aTHX_ sub_name, sub_name_len);
            if (pkg_filename_sv && SvOK(pkg_filename_sv)) {
                filename = SvPV(pkg_filename_sv, filename_len);
            if (trace_level >= 2)
                logwarn("Sub %s is xsub, we'll associate it with filename %.*s\n",
                    sub_name, (int)filename_len, filename);
            }
        }

        fid = get_file_id(aTHX_ filename, filename_len, 0);
        if (!fid) {
            if (trace_level >= 4)
                logwarn("Sub %s has no fid assigned (for file '%.*s')\n",
                    sub_name, (int)filename_len, filename);
            continue; /* no point in writing subs in files we've not profiled */
        }

        if (trace_level >= 2)
            logwarn("Sub %s fid %u lines %lu..%lu\n",
                sub_name, fid, (unsigned long)first_line, (unsigned long)last_line);

        NYTP_write_sub_info(out, fid, sub_name, sub_name_len, first_line,
                            last_line);
    }
}


static void
write_sub_callers(pTHX)
{
    char *called_subname;
    I32 called_subname_len;
    SV *fid_line_rvhv;
    int negative_time_calls = 0;

    if (!sub_callers_hv)
        return;
    if (trace_level >= 2)
        logwarn("~ writing sub callers\n");

    hv_iterinit(sub_callers_hv);
    while (NULL != (fid_line_rvhv = hv_iternextsv(sub_callers_hv, &called_subname, &called_subname_len))) {
        HV *fid_lines_hv;
        char *caller_subname;
        I32 caller_subname_len;
        SV *sv;

        if (!SvROK(fid_line_rvhv) || SvTYPE(SvRV(fid_line_rvhv))!=SVt_PVHV) {
            logwarn("bad entry %s in sub_callers_hv\n", called_subname);
            continue;
        }
        fid_lines_hv = (HV*)SvRV(fid_line_rvhv);

        if (0) {
            logwarn("Callers of %s:\n", called_subname);
            /* level, *file, *sv, I32 nest, I32 maxnest, bool dumpops, STRLEN pvlim */
            do_sv_dump(0, Perl_debug_log, fid_line_rvhv, 0, 5, 0, 100);
        }

        /* iterate over callers to this sub ({ "subname[fid:line]" => [ ... ] })  */
        hv_iterinit(fid_lines_hv);
        while (NULL != (sv = hv_iternextsv(fid_lines_hv, &caller_subname, &caller_subname_len))) {
            NV sc[NYTP_SCi_elements];
            AV *av = (AV *)SvRV(sv);
            int trace = (trace_level >= 3);
            UV count;
            UV depth;

            unsigned int fid = 0, line = 0;
            const char *fid_line_delim = "[";
            char *fid_line_start = rninstr(caller_subname, caller_subname+caller_subname_len, fid_line_delim, fid_line_delim+1);
            if (!fid_line_start) {
                logwarn("bad fid_lines_hv key '%s'\n", caller_subname);
                continue;
            }
            if (2 != sscanf(fid_line_start+1, "%u:%u", &fid, &line)) {
                logwarn("bad fid_lines_hv format '%s'\n", caller_subname);
                continue;
            }
            /* trim length to effectively hide the [fid:line] suffix */
            caller_subname_len = fid_line_start-caller_subname;

            count = uv_from_av(aTHX_ av, NYTP_SCi_CALL_COUNT, 0);
            sc[NYTP_SCi_CALL_COUNT] = count * 1.0;
            sc[NYTP_SCi_INCL_RTIME] = nv_from_av(aTHX_ av, NYTP_SCi_INCL_RTIME, 0.0);
            sc[NYTP_SCi_EXCL_RTIME] = nv_from_av(aTHX_ av, NYTP_SCi_EXCL_RTIME, 0.0);
            sc[NYTP_SCi_RECI_RTIME] = nv_from_av(aTHX_ av, NYTP_SCi_RECI_RTIME, 0.0);
            depth = uv_from_av(aTHX_ av, NYTP_SCi_REC_DEPTH , 0);
            sc[NYTP_SCi_REC_DEPTH]  = depth * 1.0;

            NYTP_write_sub_callers(out, fid, line,
                                   caller_subname, caller_subname_len,
                                   count,
                                   sc[NYTP_SCi_INCL_RTIME],
                                   sc[NYTP_SCi_EXCL_RTIME],
                                   0.0, /* NYTP_SCi_spare_3 */
                                   0.0, /* NYTP_SCi_spare_4 */
                                   sc[NYTP_SCi_RECI_RTIME],
                                   depth,
                                   called_subname, called_subname_len);

            /* sanity check - early warning */
            if (sc[NYTP_SCi_INCL_RTIME] < 0.0 || sc[NYTP_SCi_EXCL_RTIME] < 0.0) {
                ++negative_time_calls;
                if (trace_level) {
                    logwarn("%s call has negative time: incl %"NVff"s, excl %"NVff"s (clock id %d)\n",
                        called_subname, sc[NYTP_SCi_INCL_RTIME], sc[NYTP_SCi_EXCL_RTIME], profile_clock);
                    trace = 1;
                }
            }

            if (trace) {
                if (!fid && !line) {
                    logwarn("%s is xsub\n", called_subname);
                }
                else {
                    logwarn("%s called by %.*s at %u:%u: count %ld (i%"NVff"s e%"NVff"s, d%d ri%"NVff"s)\n",
                        called_subname, (int)caller_subname_len, caller_subname, fid, line,
                        (long)sc[NYTP_SCi_CALL_COUNT], sc[NYTP_SCi_INCL_RTIME], sc[NYTP_SCi_EXCL_RTIME],
                        (int)sc[NYTP_SCi_REC_DEPTH], sc[NYTP_SCi_RECI_RTIME]);
                }
            }
        }
    }
    if (negative_time_calls) {
        logwarn("Warning: %d subroutine calls had negative time! The clock being used (%d) and the results you'll get are likely to be unstable.\n",
            negative_time_calls, profile_clock);
    }
}


static void
write_src_of_files(pTHX)
{
    Hash_entry *e;
    int t_has_src  = 0;
    int t_save_src = 0;
    int t_no_src = 0;
    long t_lines = 0;

    if (trace_level >= 2)
        logwarn("~ writing file source code\n");

    for (e = hashtable.first_inserted; e; e = (Hash_entry *)e->next_inserted) {
        I32 lines;
        int line;
        AV *src_av = GvAV(gv_fetchfile_flags(e->key, e->key_len, 0));

        if ( !(e->fid_flags & NYTP_FIDf_HAS_SRC) ) {
            ++t_no_src;
            if (src_av) /* sanity check */
                logwarn("fid %d has src but NYTP_FIDf_HAS_SRC not set! (%.*s)\n",
                    e->id, e->key_len, e->key);
            continue;
        }
        if (!src_av) { /* sanity check */
            ++t_no_src;
            logwarn("fid %d has no src but NYTP_FIDf_HAS_SRC is set! (%.*s)\n",
                e->id, e->key_len, e->key);
            continue;
        }
        ++t_has_src;

        if ( !(e->fid_flags & NYTP_FIDf_SAVE_SRC) ) {
            continue;
        }
        ++t_save_src;

        lines = av_len(src_av); /* -1 is empty, 1 is 1 line etc, 0 shouldn't happen */
        if (trace_level >= 4)
            logwarn("fid %d has %ld src lines for %.*s\n",
                e->id, (long)lines, e->key_len, e->key);
        /* for perl 5.10.0 or 5.8.8 (or earlier) use_db_sub is needed to get src */
        /* give a hint for the common case */
        if (lines <= 0 && !opt_use_db_sub
            &&   ( e->key[0] == '-'
                   && ( e->key_len == 1
                        || ( e->key[1] == 'e' &&  e->key_len == 2 ) ) )
        ) {
            av_store(src_av, 1, newSVpvf("# fid%d: source not available, try using use_db_sub=1 option.\n",e->id));
            lines = 1;
        }
        for (line = 1; line <= lines; ++line) { /* lines start at 1 */
            SV **svp = av_fetch(src_av, line, 0);
            STRLEN len = 0;
            const char *src = (svp) ? SvPV(*svp, len) : "";
            /* outputting the tag and fid for each (non empty) line
             * is a little inefficient, but not enough to worry about */
            NYTP_write_src_line(out, e->id, line, src, (I32)len);    /* includes newline */
            if (trace_level >= 5) {
                logwarn("fid %d src line %d: %s%s", e->id, line, src,
                    (len && src[len-1]=='\n') ? "" : "\n");
            }
            ++t_lines;
        }
    }

    if (trace_level >= 2)
        logwarn("~ wrote %ld source lines for %d files (%d skipped without savesrc option, %d others had no source available)\n",
            t_lines, t_save_src, t_has_src-t_save_src, t_no_src);
}


/**
 * Read an integer by decompressing the next 1 to 4 bytes of binary into a 32-
 * bit integer. See output_int() for the compression details.
 */
static unsigned int
read_int(NYTP_file ifile)
{
    unsigned char d;
    unsigned int newint;

    NYTP_read(ifile, &d, sizeof(d), "integer prefix");

    if (d < 0x80) {                               /* 7 bits */
        newint = d;
    }
    else {
        unsigned char buffer[4];
        unsigned char *p = buffer;
        unsigned int length;

        if (d < 0xC0) {                          /* 14 bits */
            newint = d & 0x7F;
            length = 1;
        }
        else if (d < 0xE0) {                          /* 21 bits */
            newint = d & 0x1F;
            length = 2;
        }
        else if (d < 0xFF) {                          /* 28 bits */
            newint = d & 0xF;
            length = 3;
        }
        else if (d == 0xFF) {                         /* 32 bits */
            newint = 0;
            length = 4;
        }
        NYTP_read(ifile, buffer, length, "integer");
        while (length--) {
            newint <<= 8;
            newint |= *p++;
        }
    }
    return newint;
}


/**
 * Read an NV by simple byte copy to memory
 */
static NV
read_nv(NYTP_file ifile)
{
    NV nv;
    /* no error checking on the assumption that a later token read will
     * detect the error/eof condition
     */
    NYTP_read(ifile, (unsigned char *)&nv, sizeof(NV), "float");
    return nv;
}


static void
normalize_eval_seqn(pTHX_ SV *sv) {
    /* in-place-edit any eval sequence numbers to 0 */
    STRLEN len;
    char *start = SvPV(sv, len);
    char *first_space;

    /* effectively does
       s/(
          \(                  # first character is literal (
          (?:re_)?eval\       # eval or re_eval followed by space
         )                    # [capture that]
         [0-9]+               # digits
         (?=\))               # look ahead for literal )
         /$1 0/xg             # and rebuild, replacing the digts with 0
    */

    /* Assumption is that space is the least common character in a filename.  */

    for (; len >= 8 && (first_space = (char *)memchr(start, ' ', len));
         (len -= first_space +1 - start), (start = first_space + 1)) {
        char *first_digit;
        char *close;

        if (!((first_space - start >= 5
               && memEQ(first_space - 5, "(eval", 5))
              || (first_space - start >= 8
                  && memEQ(first_space - 8, "(re_eval", 8)))) {
            /* Fixed string not found. Try again.  */
            continue;
        }

        first_digit = first_space + 1;
        if (*first_digit < '0' || *first_digit > '9')
            continue;

        close = first_digit + 1;

        while (*close >= '0' && *close <= '9')
            ++close;

        if (*close != ')')
            continue;

        if (trace_level >= 5)
            logwarn("found eval at '%s' in %s\n", first_digit, start);

        *first_digit++ = '0';

        /* first_digit now points to the target of the move.  */

        if (close != first_digit) {
            /* 2 or more digits */
            memmove(first_digit, close,
                    start + len + 1 /* pointer beyond the trailing '\0'  */
                    - close);       /* pointer to the )  */

            len -= (close - first_digit);
            SvCUR_set(sv, SvCUR(sv) - (close - first_digit));
        }

        if (trace_level >= 5)
            logwarn("edited it to: %s\n", start);
    }
}


static AV *
lookup_subinfo_av(pTHX_ SV *subname_sv, HV *sub_subinfo_hv)
{
    /* { 'pkg::sub' => [
     *      fid, first_line, last_line, incl_time
     *    ], ... }
     */
    HE *he = hv_fetch_ent(sub_subinfo_hv, subname_sv, 1, 0);
    SV *sv = HeVAL(he);
    if (!SvROK(sv)) {                             /* autoviv */
        AV *av = newAV();
        SV *rv = newRV_noinc((SV *)av);
        /* 0: fid - may be undef
         * 1: start_line - may be undef if not known and not known to be xs
         * 2: end_line - ditto
         */
        sv_setsv(*av_fetch(av, NYTP_SIi_SUB_NAME,   1), newSVsv(subname_sv));
        sv_setuv(*av_fetch(av, NYTP_SIi_CALL_COUNT, 1),   0); /* call count */
        sv_setnv(*av_fetch(av, NYTP_SIi_INCL_RTIME, 1), 0.0); /* incl_time */
        sv_setnv(*av_fetch(av, NYTP_SIi_EXCL_RTIME, 1), 0.0); /* excl_time */
        sv_setsv(*av_fetch(av, NYTP_SIi_PROFILE,    1), &PL_sv_undef); /* ref to profile */
        sv_setuv(*av_fetch(av, NYTP_SIi_REC_DEPTH,  1),   0); /* rec_depth */
        sv_setnv(*av_fetch(av, NYTP_SIi_RECI_RTIME, 1), 0.0); /* reci_time */
        sv_setsv(sv, rv);
    }
    return (AV *)SvRV(sv);
}


static void
store_attrib_sv(pTHX_ HV *attr_hv, const char *text, STRLEN text_len, SV *value_sv)
{
    (void)hv_store(attr_hv, text, text_len, value_sv, 0);
    if (trace_level >= 1)
        logwarn(": %.*s = '%s'\n", (int) text_len, text, SvPV_nolen(value_sv));
}

static int
eval_outer_fid(pTHX_
    AV *fid_fileinfo_av,
    unsigned int fid,
    int recurse,
    unsigned int *eval_file_num_ptr,
    unsigned int *eval_line_num_ptr
) {
    unsigned int outer_fid;
    AV *av;
    SV *fid_info_rvav = *av_fetch(fid_fileinfo_av, fid, 1);
    if (!SvROK(fid_info_rvav)) /* should never happen */
        return 0;
    av = (AV *)SvRV(fid_info_rvav);
    outer_fid = (unsigned int)SvUV(*av_fetch(av,NYTP_FIDi_EVAL_FID,1));
    if (!outer_fid)
        return 0;
    if (outer_fid == fid) {
        logwarn("Possible corruption: eval_outer_fid of %d is %d!\n", fid, outer_fid);
        return 0;
    }
    if (eval_file_num_ptr)
        *eval_file_num_ptr = outer_fid;
    if (eval_line_num_ptr)
        *eval_line_num_ptr = (unsigned int)SvUV(*av_fetch(av,NYTP_FIDi_EVAL_LINE,1));
    if (recurse)
        eval_outer_fid(aTHX_ fid_fileinfo_av, outer_fid, recurse, eval_file_num_ptr, eval_line_num_ptr);
    return 1;
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
static HV*
load_profile_data_from_stream(SV *cb)
{
    dTHX;
    dSP;
    int file_major, file_minor;

    unsigned long input_chunk_seqn = 0L;
    unsigned int last_file_num = 0;
    unsigned int last_line_num = 0;
    int statement_discount = 0;
    NV total_stmts_duration = 0.0;
    int total_stmts_measured = 0;
    int total_stmts_discounted = 0;
    int total_sub_calls = 0;
    HV *profile_hv;
    HV* profile_modes = newHV();
    HV *live_pids_hv = newHV();
    HV *attr_hv = newHV();
    AV* fid_fileinfo_av = newAV();
    AV* fid_srclines_av = newAV();
    AV* fid_line_time_av = newAV();
    AV* fid_block_time_av = NULL;
    AV* fid_sub_time_av = NULL;
    HV* sub_subinfo_hv = newHV();
    SV *tmp_str1_sv = newSVpvn("",0);
    SV *tmp_str2_sv = newSVpvn("",0);
    HV *file_info_stash = gv_stashpv("Devel::NYTProf::FileInfo", GV_ADDWARN);

    /* these times don't reflect profile_enable & profile_disable calls */
    NV profiler_start_time = 0.0;
    NV profiler_end_time = 0.0;
    NV profiler_duration = 0.0;

    /* callback support */
    int i;
    SV *input_chunk_seqn_sv = NULL;
    SV *cb_DISCOUNT_tag = NULL;
    SV *cb_TIME_BLOCK_tag = NULL;
    SV *cb_TIME_LINE_tag = NULL;
    SV *cb_args[12];  /* must be large enough for the largest callback argument list */

    size_t buffer_len = MAXPATHLEN * 2;
    char *buffer = (char *)safemalloc(buffer_len);

    av_extend(fid_fileinfo_av, 64);               /* grow them up front. */
    av_extend(fid_srclines_av, 64);
    av_extend(fid_line_time_av, 64);

    if (1) {
        if (!NYTP_gets(in, &buffer, &buffer_len))
            croak("NYTProf data format error while reading header");
        if (2 != sscanf(buffer, "NYTProf %d %d\n", &file_major, &file_minor))
            croak("NYTProf data format error while parsing header");
        if (file_major != 3)
            croak("NYTProf data format version %d.%d is not supported by NYTProf %s (which expects version %d.%d)",
                file_major, file_minor, XS_VERSION, NYTP_FILE_MAJOR_VERSION, NYTP_FILE_MINOR_VERSION);

        if (file_minor > NYTP_FILE_MINOR_VERSION)
            warn("NYTProf data format version %d.%d is newer than that understood by this NYTProf %s, so errors are likely",
                file_major, file_minor, XS_VERSION);
    }

    if (cb && SvROK(cb)) {
        input_chunk_seqn_sv = save_scalar(gv_fetchpv(".", GV_ADD, SVt_IV));
        sv_setuv(input_chunk_seqn_sv, input_chunk_seqn);

        /* these tags are frequent enough that we reuse the same SV in all calls */
        cb_DISCOUNT_tag = sv_2mortal(newSVpvs("DISCOUNT"));
        cb_TIME_BLOCK_tag = sv_2mortal(newSVpvs("TIME_BLOCK"));
        cb_TIME_LINE_tag = sv_2mortal(newSVpvs("TIME_LINE"));
        SvREADONLY_on(cb_DISCOUNT_tag);
        SvREADONLY_on(cb_TIME_BLOCK_tag);
        SvREADONLY_on(cb_TIME_LINE_tag);

        for (i = 0; i < C_ARRAY_LENGTH(cb_args); i++)
            cb_args[i] = sv_newmortal();

        PUSHMARK(SP);
        i = 0;
        sv_setpvs(cb_args[i], "VERSION");  XPUSHs(cb_args[i++]);
        sv_setiv(cb_args[i], file_major);  XPUSHs(cb_args[i++]);
        sv_setiv(cb_args[i], file_minor);  XPUSHs(cb_args[i++]);
        PUTBACK;
        call_sv(cb, G_DISCARD);
        SPAGAIN;
    }
    else {
        cb = Nullsv;
    }

    while (1) {
        /* Loop "forever" until EOF. We can only check the EOF flag *after* we
           attempt a read.  */
        char c;

        if (NYTP_read_unchecked(in, &c, sizeof(c)) != sizeof(c)) {
          if (NYTP_eof(in))
            break;
          croak("Profile format error '%s' whilst reading tag at %ld",
                NYTP_fstrerror(in), NYTP_tell(in));
        }

        input_chunk_seqn++;
        if (cb) {
            sv_setuv_mg(input_chunk_seqn_sv, input_chunk_seqn);
        }

        if (trace_level >= 6)
            logwarn("Chunk %lu token is %d ('%c') at %ld%s\n", input_chunk_seqn, c, c, NYTP_tell(in)-1, NYTP_type_of_offset(in));

        switch (c) {
            case NYTP_TAG_DISCOUNT:
            {
                if (cb) {
                    PUSHMARK(SP);
                    XPUSHs(cb_DISCOUNT_tag);
                    PUTBACK;
                    call_sv(cb, G_DISCARD);
                    SPAGAIN;
                    break;
                }

                if (trace_level >= 4)
                    logwarn("discounting next statement after %u:%d\n", last_file_num, last_line_num);
                if (statement_discount)
                    logwarn("multiple statement discount after %u:%d\n", last_file_num, last_line_num);
                ++statement_discount;
                ++total_stmts_discounted;
                break;
            }

            case NYTP_TAG_TIME_LINE:                       /*FALLTHRU*/
            case NYTP_TAG_TIME_BLOCK:
            {
                char trace_note[80] = "";
                SV *fid_info_rvav;
                NV seconds;
                unsigned int eval_file_num = 0;
                unsigned int eval_line_num = 0;
                unsigned int ticks    = read_int(in);
                unsigned int file_num = read_int(in);
                unsigned int line_num = read_int(in);
                unsigned int block_line_num = 0;
                unsigned int sub_line_num = 0;

                if (c == NYTP_TAG_TIME_BLOCK) {
                    block_line_num = read_int(in);
                    sub_line_num = read_int(in);
                }

                if (cb) {
                    PUSHMARK(SP);

                    XPUSHs(c == NYTP_TAG_TIME_BLOCK ? cb_TIME_BLOCK_tag : cb_TIME_LINE_tag);

                    i = 0;
                    sv_setiv(cb_args[i], eval_file_num);  XPUSHs(cb_args[i++]);
                    sv_setiv(cb_args[i], eval_line_num);  XPUSHs(cb_args[i++]);
                    sv_setiv(cb_args[i], ticks);          XPUSHs(cb_args[i++]);
                    sv_setiv(cb_args[i], file_num);       XPUSHs(cb_args[i++]);
                    sv_setiv(cb_args[i], line_num);       XPUSHs(cb_args[i++]);

                    if (c == NYTP_TAG_TIME_BLOCK) {
                        sv_setiv(cb_args[i], block_line_num); XPUSHs(cb_args[i++]);
                        sv_setiv(cb_args[i], sub_line_num); XPUSHs(cb_args[i++]);
                    }

                    PUTBACK;
                    call_sv(cb, G_DISCARD);
                    SPAGAIN;
                    break;
                }

                seconds  = (NV)ticks / ticks_per_sec;

                fid_info_rvav = *av_fetch(fid_fileinfo_av, file_num, 1);
                if (!SvROK(fid_info_rvav)) {    /* should never happen */
                    if (!SvOK(fid_info_rvav)) { /* only warn once */
                        logwarn("Fid %u used but not defined\n", file_num);
                        sv_setsv(fid_info_rvav, &PL_sv_no);
                    }
                }
                else {
                    eval_outer_fid(aTHX_ fid_fileinfo_av, file_num, 1, &eval_file_num, &eval_line_num);
                }

                if (eval_file_num) {              /* fid is an eval */
                    if (trace_level >= 3)
                        sprintf(trace_note," (was string eval fid %u)", file_num);
                    file_num = eval_file_num;
                }
                if (trace_level >= 4) {
                    const char *new_file_name = "";
                    if (file_num != last_file_num && SvROK(fid_info_rvav))
                        new_file_name = SvPV_nolen(*av_fetch((AV *)SvRV(fid_info_rvav), NYTP_FIDi_FILENAME, 1));
                    logwarn("Read %d:%-4d %2u ticks%s %s\n",
                        file_num, line_num, ticks, trace_note, new_file_name);
                }

                add_entry(aTHX_ fid_line_time_av, file_num, line_num,
                    seconds, eval_file_num, eval_line_num,
                    1-statement_discount
                );

                if (c == NYTP_TAG_TIME_BLOCK) {
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

                    if (trace_level >= 4)
                        logwarn("\tblock %u, sub %u\n", block_line_num, sub_line_num);
                }

                total_stmts_measured++;
                total_stmts_duration += seconds;
                statement_discount = 0;
                last_file_num = file_num;
                last_line_num = line_num;
                break;
            }

            case NYTP_TAG_NEW_FID:                             /* file */
            {
                AV *av;
                SV *rv;
                SV **svp;
                SV *filename_sv;
                unsigned int file_num      = read_int(in);
                unsigned int eval_file_num = read_int(in);
                unsigned int eval_line_num = read_int(in);
                unsigned int fid_flags     = read_int(in);
                unsigned int file_size     = read_int(in);
                unsigned int file_mtime    = read_int(in);

                filename_sv = read_str(aTHX_ in, NULL);

                if (cb) {
                    PUSHMARK(SP);

                    i = 0;
                    sv_setpvs(cb_args[i], "NEW_FID");    XPUSHs(cb_args[i++]);
                    sv_setiv(cb_args[i], file_num);      XPUSHs(cb_args[i++]);
                    sv_setiv(cb_args[i], eval_file_num); XPUSHs(cb_args[i++]);
                    sv_setiv(cb_args[i], eval_line_num); XPUSHs(cb_args[i++]);
                    sv_setiv(cb_args[i], fid_flags);     XPUSHs(cb_args[i++]);
                    sv_setiv(cb_args[i], file_size);     XPUSHs(cb_args[i++]);
                    sv_setiv(cb_args[i], file_mtime);    XPUSHs(cb_args[i++]);
                    assert(i <= C_ARRAY_LENGTH(cb_args));

                    XPUSHs(sv_2mortal(filename_sv));

                    PUTBACK;
                    call_sv(cb, G_DISCARD);
                    SPAGAIN;
                    break;
                }

                if (eval_file_num)
                    normalize_eval_seqn(aTHX_ filename_sv);

                if (trace_level >= 2) {
                    SV *fid_flags_sv = fmt_fid_flags(aTHX_ fid_flags, NULL);
                    char parent_fid[80];
                    if (eval_file_num || eval_line_num)
                         sprintf(parent_fid, " (is eval at %u:%u)", eval_file_num, eval_line_num);
                    else 
                         sprintf(parent_fid, " (file sz%d mt%d)", file_size, file_mtime);

                    logwarn("Fid %2u is %s%s 0x%x(%s)\n",
                        file_num, SvPV_nolen(filename_sv), parent_fid,
                        fid_flags, SvPV_nolen(fid_flags_sv));
                }

                /* [ name, eval_file_num, eval_line_num, fid, flags, size, mtime, ... ]
                 */
                av = newAV();
                rv = newRV_noinc((SV*)av);
                sv_bless(rv, file_info_stash);

                svp = av_fetch(fid_fileinfo_av, file_num, 1);
                if (SvOK(*svp)) { /* should never happen, perhaps file is corrupt */
                    AV *old_av = (AV *)SvRV(*av_fetch(fid_fileinfo_av, file_num, 1));
                    SV *old_name = *av_fetch(old_av, 0, 1);
                    logwarn("Fid %d redefined from %s to %s\n", file_num,
                        SvPV_nolen(old_name), SvPV_nolen(filename_sv));
                }
                sv_setsv(*svp, rv);

                av_store(av, NYTP_FIDi_FILENAME, filename_sv); /* av now owns the sv */
                if (eval_file_num) {
                    SV *has_evals;
                    /* this eval fid refers to the fid that contained the eval */
                    SV *eval_fi = *av_fetch(fid_fileinfo_av, eval_file_num, 1);
                    if (!SvROK(eval_fi)) { /* should never happen */
                        logwarn("Eval '%s' (fid %d) has unknown invoking fid %d\n",
                            SvPV_nolen(filename_sv), file_num, eval_file_num);
                        /* so make it look like a real file instead of an eval */
                        av_store(av, NYTP_FIDi_EVAL_FI,   &PL_sv_undef);
                        eval_file_num = 0;
                        eval_line_num = 0;
                    }
                    else {
                        av_store(av, NYTP_FIDi_EVAL_FI, sv_rvweaken(newSVsv(eval_fi)));
                        /* the fid that contained the eval has a list of eval fids */
                        has_evals = *av_fetch((AV *)SvRV(eval_fi), NYTP_FIDi_HAS_EVALS, 1);
                        if (!SvROK(has_evals)) /* autoviv */
                            sv_setsv(has_evals, newRV_noinc((SV*)newAV()));
                        av_push((AV *)SvRV(has_evals), sv_rvweaken(newSVsv(rv)));
                    }
                }
                else {
                    av_store(av, NYTP_FIDi_EVAL_FI,   &PL_sv_undef);
                }
                av_store(av, NYTP_FIDi_EVAL_FID,  (eval_file_num) ? newSVuv(eval_file_num) : &PL_sv_no);
                av_store(av, NYTP_FIDi_EVAL_LINE, (eval_file_num) ? newSVuv(eval_line_num) : &PL_sv_no);
                av_store(av, NYTP_FIDi_FID,       newSVuv(file_num));
                av_store(av, NYTP_FIDi_FLAGS,     newSVuv(fid_flags));
                av_store(av, NYTP_FIDi_FILESIZE,  newSVuv(file_size));
                av_store(av, NYTP_FIDi_FILEMTIME, newSVuv(file_mtime));
                av_store(av, NYTP_FIDi_PROFILE,   &PL_sv_undef);
                av_store(av, NYTP_FIDi_HAS_EVALS, &PL_sv_undef);
                av_store(av, NYTP_FIDi_SUBS_DEFINED, newRV_noinc((SV*)newHV()));
                av_store(av, NYTP_FIDi_SUBS_CALLED,  newRV_noinc((SV*)newHV()));

                break;
            }

            case NYTP_TAG_SRC_LINE:
            {
                unsigned int file_num = read_int(in);
                unsigned int line_num = read_int(in);
                SV *src = read_str(aTHX_ in, NULL);
                AV *file_av;

                if (cb) {
                    PUSHMARK(SP);

                    i = 0;
                    sv_setpvs(cb_args[i], "SRC_LINE");  XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], file_num);     XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], line_num);     XPUSHs(cb_args[i++]);

                    XPUSHs(sv_2mortal(src));

                    PUTBACK;
                    call_sv(cb, G_DISCARD);
                    SPAGAIN;
                    break;
                }

                /* first line in the file seen */
                if (!av_exists(fid_srclines_av, file_num)) {
                    file_av = newAV();
                    av_store(fid_srclines_av, file_num, newRV_noinc((SV*)file_av));
                }
                else {
                    file_av = (AV *)SvRV(*av_fetch(fid_srclines_av, file_num, 1));
                }

                av_store(file_av, line_num, src);

                if (trace_level >= 4) {
                    logwarn("Fid %2u:%u: %s\n", file_num, line_num, SvPV_nolen(src));
                }
                break;
            }

            case NYTP_TAG_SUB_INFO:
            {
                AV *av;
                SV *sv;
                unsigned int fid        = read_int(in);
                SV *subname_sv = read_str(aTHX_ in, tmp_str1_sv);
                unsigned int first_line = read_int(in);
                unsigned int last_line  = read_int(in);
                int skip_subinfo_store = 0;
                STRLEN subname_len;
                char *subname_pv;
                int extra_items = read_int(in);

                while (extra_items-- > 0)
                    (void)read_int(in);

                if (cb) {
                    PUSHMARK(SP);

                    i = 0;
                    sv_setpvs(cb_args[i], "SUB_INFO"); XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], fid);         XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], first_line);  XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], last_line);   XPUSHs(cb_args[i++]);
                    sv_setsv(cb_args[i], subname_sv);  XPUSHs(cb_args[i++]);

                    PUTBACK;
                    call_sv(cb, G_DISCARD);
                    SPAGAIN;
                    break;
                }

                normalize_eval_seqn(aTHX_ subname_sv);

                subname_pv = SvPV(subname_sv, subname_len);
                if (trace_level >= 2)
                    logwarn("Sub %s fid %u lines %u..%u\n",
                        subname_pv, fid, first_line, last_line);

                av = lookup_subinfo_av(aTHX_ subname_sv, sub_subinfo_hv);
                if (SvOK(*av_fetch(av, NYTP_SIi_FID, 1))) {
                    /* We've already seen this subroutine name.
                     * Should only happen for anon subs in string evals so we warn
                     * for other cases.
                     */
                    if (!instr(subname_pv, "__ANON__[(eval"))
                        logwarn("Sub %s already defined!\n", subname_pv);

                    /* We could always discard the fid+first_line+last_line here,
                     * because we already have them stored, but for consistency
                     * (and for the stability of the tests) we'll prefer the lowest fid
                     */
                    if (fid > SvUV(*av_fetch(av, NYTP_SIi_FID, 1)))
                        skip_subinfo_store = 1;

                    /* Finally, note that the fileinfo NYTP_FIDi_SUBS_DEFINED hash,
                     * updated below, does get an entry for the sub *from each fid*
                     * (ie string eval) that defines the subroutine.
                     */
                }
                if (!skip_subinfo_store) {
                    sv_setuv(*av_fetch(av, NYTP_SIi_FID,        1), fid);
                    sv_setuv(*av_fetch(av, NYTP_SIi_FIRST_LINE, 1), first_line);
                    sv_setuv(*av_fetch(av, NYTP_SIi_LAST_LINE,  1), last_line);
                }

                /* add sub to NYTP_FIDi_SUBS_DEFINED hash */
                sv = SvRV(*av_fetch(fid_fileinfo_av, fid, 1));
                sv = SvRV(*av_fetch((AV *)sv, NYTP_FIDi_SUBS_DEFINED, 1));
                (void)hv_store((HV *)sv, subname_pv, (I32)subname_len, newRV_inc((SV*)av), 0);

                break;
            }

            case NYTP_TAG_SUB_CALLERS:
            {
                char text[MAXPATHLEN*2];
                SV *sv;
                AV *subinfo_av;
                int len;
                unsigned int fid   = read_int(in);
                unsigned int line  = read_int(in);
                SV *caller_subname_sv = read_str(aTHX_ in, tmp_str2_sv);
                unsigned int count = read_int(in);
                NV incl_time       = read_nv(in);
                NV excl_time       = read_nv(in);
                NV spare_3         = read_nv(in);
                NV spare_4         = read_nv(in);
                NV reci_time       = read_nv(in);
                UV rec_depth       = read_int(in);
                SV *called_subname_sv = read_str(aTHX_ in, tmp_str1_sv);

                PERL_UNUSED_VAR(spare_3);
                PERL_UNUSED_VAR(spare_4);

                if (cb) {
                    PUSHMARK(SP);

                    i = 0;
                    sv_setpvs(cb_args[i], "SUB_CALLERS"); XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], fid);            XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], line);           XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], count);          XPUSHs(cb_args[i++]);
                    sv_setnv(cb_args[i], incl_time);      XPUSHs(cb_args[i++]);
                    sv_setnv(cb_args[i], excl_time);      XPUSHs(cb_args[i++]);
                    sv_setnv(cb_args[i], 0.0);            XPUSHs(cb_args[i++]);
                    sv_setnv(cb_args[i], 0.0);            XPUSHs(cb_args[i++]);
                    sv_setnv(cb_args[i], reci_time);      XPUSHs(cb_args[i++]);
                    sv_setiv(cb_args[i], rec_depth);      XPUSHs(cb_args[i++]);
                    sv_setsv(cb_args[i], called_subname_sv);     XPUSHs(cb_args[i++]);
                    sv_setsv(cb_args[i], caller_subname_sv);     XPUSHs(cb_args[i++]);
                    assert(i <= C_ARRAY_LENGTH(cb_args));

                    PUTBACK;
                    call_sv(cb, G_DISCARD);
                    SPAGAIN;
                    break;
                }

                normalize_eval_seqn(aTHX_ caller_subname_sv);
                normalize_eval_seqn(aTHX_ called_subname_sv);

                if (trace_level >= 3)
                    logwarn("Sub %s called by %s %u:%u: count %d, incl %"NVff", excl %"NVff"\n",
                        SvPV_nolen(called_subname_sv), SvPV_nolen(caller_subname_sv), fid, line,
                        count, incl_time, excl_time);

                subinfo_av = lookup_subinfo_av(aTHX_ called_subname_sv, sub_subinfo_hv);

                /* { caller_fid => { caller_line => [ count, incl_time, ... ] } } */
                sv = *av_fetch(subinfo_av, NYTP_SIi_CALLED_BY, 1);
                if (!SvROK(sv))                   /* autoviv */
                    sv_setsv(sv, newRV_noinc((SV*)newHV()));

                len = sprintf(text, "%u", fid);
                sv = *hv_fetch((HV*)SvRV(sv), text, len, 1);
                if (!SvROK(sv))                   /* autoviv */
                    sv_setsv(sv, newRV_noinc((SV*)newHV()));

                if (fid) {
                    SV *fi;
                    AV *av;
                    len = sprintf(text, "%u", line);

                    sv = *hv_fetch((HV*)SvRV(sv), text, len, 1);
                    if (!SvROK(sv))               /* autoviv */
                        sv_setsv(sv, newRV_noinc((SV*)newAV()));
                    else if (trace_level)
                        /* calls to sub1 from the same fid:line could have different caller subs
                         * due to evals or if profile_findcaller is off.
                         */
                        logwarn("Merging extra sub caller info for %s called at %d:%d\n",
                            SvPV_nolen(called_subname_sv), fid, line);
                    av = (AV *)SvRV(sv);
                    sv = *av_fetch(av, NYTP_SCi_CALL_COUNT, 1);
                    sv_setuv(sv, (SvOK(sv)) ? SvUV(sv) + count : count);
                    sv = *av_fetch(av, NYTP_SCi_INCL_RTIME, 1);
                    sv_setnv(sv, (SvOK(sv)) ? SvNV(sv) + incl_time : incl_time);
                    sv = *av_fetch(av, NYTP_SCi_EXCL_RTIME, 1);
                    sv_setnv(sv, (SvOK(sv)) ? SvNV(sv) + excl_time : excl_time);
                    sv = *av_fetch(av, NYTP_SCi_spare_3, 1);
                    sv_setnv(sv, 0.0);
                    sv = *av_fetch(av, NYTP_SCi_spare_4, 1);
                    sv_setnv(sv, 0.0);
                    sv = *av_fetch(av, NYTP_SCi_RECI_RTIME, 1);
                    sv_setnv(sv, (SvOK(sv)) ? SvNV(sv) + reci_time : reci_time);
                    sv = *av_fetch(av, NYTP_SCi_REC_DEPTH,  1);
                    if (!SvOK(sv) || SvUV(sv) < rec_depth) /* max() */
                        sv_setuv(sv, rec_depth);

                    /* XXX temp hack way to store calling subname */
                    sv = *av_fetch(av, NYTP_SCi_CALLING_SUB, 1);
                    if (!SvROK(sv))               /* autoviv */
                        sv_setsv(sv, newRV_noinc((SV*)newHV()));
                    (void)hv_fetch_ent((HV *)SvRV(sv), caller_subname_sv, 1, 0);

                    /* add sub call to NYTP_FIDi_SUBS_CALLED hash of fid making the call */
                    /* => { line => { subname => [ ... ] } } */
                    fi = SvRV(*av_fetch(fid_fileinfo_av, fid, 1));
                    fi = *av_fetch((AV *)fi, NYTP_FIDi_SUBS_CALLED, 1);
                    fi = *hv_fetch((HV*)SvRV(fi), text, len, 1);
                    if (!SvROK(fi))               /* autoviv */
                        sv_setsv(fi, newRV_noinc((SV*)newHV()));
                    fi = HeVAL(hv_fetch_ent((HV *)SvRV(fi), called_subname_sv, 1, 0));
                    sv_setsv(fi, newRV_inc((SV *)av));
                }
                else {                            /* is meta-data about sub */
                    /* line == 0: is_xs - set line range to 0,0 as marker */
                    sv_setiv(*av_fetch(subinfo_av, NYTP_SIi_FIRST_LINE, 1), 0);
                    sv_setiv(*av_fetch(subinfo_av, NYTP_SIi_LAST_LINE,  1), 0);
                }

                /* accumulate per-sub totals into subinfo */
                sv = *av_fetch(subinfo_av, NYTP_SIi_CALL_COUNT, 1);
                sv_setuv(sv, count     + (SvOK(sv) ? SvUV(sv) : 0));
                sv = *av_fetch(subinfo_av, NYTP_SIi_INCL_RTIME, 1);
                sv_setnv(sv, incl_time + (SvOK(sv) ? SvNV(sv) : 0.0));
                sv = *av_fetch(subinfo_av, NYTP_SIi_EXCL_RTIME, 1);
                sv_setnv(sv, excl_time + (SvOK(sv) ? SvNV(sv) : 0.0));
                /* sub rec_depth - record the maximum */
                sv = *av_fetch(subinfo_av, NYTP_SIi_REC_DEPTH, 1);
                if (!SvOK(sv) || rec_depth > SvUV(sv))
                    sv_setuv(sv, rec_depth);
                sv = *av_fetch(subinfo_av, NYTP_SIi_RECI_RTIME, 1);
                sv_setnv(sv, reci_time + (SvOK(sv) ? SvNV(sv) : 0.0));

                total_sub_calls += count;
                break;
            }

            case NYTP_TAG_PID_START:
            {
                char text[MAXPATHLEN*2];
                unsigned int pid  = read_int(in);
                unsigned int ppid = read_int(in);
                int len;
                profiler_start_time = read_nv(in);

                if (cb) {
                    PUSHMARK(SP);

                    i = 0;
                    sv_setpvs(cb_args[i], "PID_START");   XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], pid);            XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], ppid);           XPUSHs(cb_args[i++]);
                    sv_setnv(cb_args[i], profiler_start_time); XPUSHs(cb_args[i++]);

                    PUTBACK;
                    call_sv(cb, G_DISCARD);
                    SPAGAIN;
                    break;
                }

                len = sprintf(text, "%d", pid);
                (void)hv_store(live_pids_hv, text, len, newSVuv(ppid), 0);
                if (trace_level)
                    logwarn("Start of profile data for pid %s (ppid %d, %"IVdf" pids live) at %"NVff"\n",
                        text, ppid, HvKEYS(live_pids_hv), profiler_start_time);

                store_attrib_sv(aTHX_ attr_hv, STR_WITH_LEN("profiler_start_time"), newSVnv(profiler_start_time));

                break;
            }

            case NYTP_TAG_PID_END:
            {
                char text[MAXPATHLEN*2];
                unsigned int pid = read_int(in);
                int len;
                profiler_end_time = read_nv(in);

                if (cb) {
                    PUSHMARK(SP);

                    i = 0;
                    sv_setpvs(cb_args[i], "PID_END");  XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], pid);         XPUSHs(cb_args[i++]);
                    sv_setnv(cb_args[i], profiler_end_time);  XPUSHs(cb_args[i++]);

                    PUTBACK;
                    call_sv(cb, G_DISCARD);
                    SPAGAIN;
                    break;
                }

                len = sprintf(text, "%d", pid);
                if (!hv_delete(live_pids_hv, text, len, 0))
                    logwarn("Inconsistent pids in profile data (pid %d not introduced)\n",
                        pid);
                if (trace_level)
                    logwarn("End of profile data for pid %s (%"IVdf" remaining) at %"NVff"\n", text,
                        HvKEYS(live_pids_hv), profiler_end_time);

                store_attrib_sv(aTHX_ attr_hv, STR_WITH_LEN("profiler_end_time"), newSVnv(profiler_end_time));
                profiler_duration += profiler_end_time - profiler_start_time;
                store_attrib_sv(aTHX_ attr_hv, STR_WITH_LEN("profiler_duration"), newSVnv(profiler_duration));

                break;
            }

            case NYTP_TAG_ATTRIBUTE:
            {
                char *value, *key_end;
                char *end = NYTP_gets(in, &buffer, &buffer_len);
                if (NULL == end)
                    /* probably EOF */
                    croak("Profile format error reading attribute");
                --end; /* End, as returned, points 1 after the \n  */
                if ((NULL == (value = (char *)memchr(buffer, '=', end - buffer)))) {
                    logwarn("attribute malformed '%s'\n", buffer);
                    continue;
                }
                key_end = value++;

                if (cb) {
                    PUSHMARK(SP);

                    i = 0;
                    sv_setpvs(cb_args[i], "ATTRIBUTE");  XPUSHs(cb_args[i++]);
                    sv_setpvn(cb_args[i], buffer, key_end - buffer); XPUSHs(cb_args[i++]);
                    sv_setpvn(cb_args[i], value, end - value);    XPUSHs(cb_args[i++]);

                    PUTBACK;
                    call_sv(cb, G_DISCARD);
                    SPAGAIN;
                } else {
                    store_attrib_sv(aTHX_ attr_hv, buffer, key_end - buffer, newSVpvn(value, end - value));
                }
                if (memEQs(buffer, key_end - buffer, "ticks_per_sec")) {
                    ticks_per_sec = (unsigned int)atoi(value);
                }
                else if (memEQs(buffer, key_end - buffer, "nv_size")) {
                    if (sizeof(NV) != atoi(value))
                        croak("Profile data created by incompatible perl config (NV size %d but ours is %d)",
                            atoi(value), (int)sizeof(NV));
                }
                    
                break;
            }

            case NYTP_TAG_COMMENT:
            {
                char *end = NYTP_gets(in, &buffer, &buffer_len);
                if (!end)
                    /* probably EOF */
                    croak("Profile format error reading comment");

                if (cb) {
                    PUSHMARK(SP);

                    i = 0;
                    sv_setpvs(cb_args[i], "COMMENT"); XPUSHs(cb_args[i++]);
                    sv_setpvn(cb_args[i], buffer, end - buffer); XPUSHs(cb_args[i++]);

                    PUTBACK;
                    call_sv(cb, G_DISCARD);
                    SPAGAIN;
                    break;
                }

                if (trace_level >= 1)
                    logwarn("# %s", buffer); /* includes \n */
                break;
            }

            case NYTP_TAG_START_DEFLATE:
            {
#ifdef HAS_ZLIB
                if (cb) {
                    PUSHMARK(SP);

                    i = 0;
                    sv_setpvs(cb_args[i], "START_DEFLATE"); XPUSHs(cb_args[i++]);

                    PUTBACK;
                    call_sv(cb, G_DISCARD);
                    SPAGAIN;
                }
                NYTP_start_inflate(in);
#else
                croak("File uses compression but compression is not supported by this build of NYTProf");
#endif
                break;
            }

            default:
                croak("File format error: token %d ('%c'), chunk %lu, pos %ld%s",
                      c, c, input_chunk_seqn, NYTP_tell(in)-1, NYTP_type_of_offset(in));
        }
    }

    if (HvKEYS(live_pids_hv)) {
        logwarn("profile data possibly truncated, no terminator for %"IVdf" pids\n",
            HvKEYS(live_pids_hv));
        store_attrib_sv(aTHX_ attr_hv, STR_WITH_LEN("complete"), &PL_sv_no);
    }
    else {
        store_attrib_sv(aTHX_ attr_hv, STR_WITH_LEN("complete"), &PL_sv_yes);
    }

    sv_free((SV*)live_pids_hv);
    sv_free(tmp_str1_sv);
    sv_free(tmp_str2_sv);
    Safefree(buffer);

    if (cb) {
        SvREFCNT_dec(profile_modes);
        SvREFCNT_dec(attr_hv);
        SvREFCNT_dec(fid_fileinfo_av);
        SvREFCNT_dec(fid_srclines_av);
        SvREFCNT_dec(fid_line_time_av);
        SvREFCNT_dec(fid_block_time_av);
        SvREFCNT_dec(fid_sub_time_av);
        SvREFCNT_dec(sub_subinfo_hv);

        return newHV(); /* dummy */
    }

    if (statement_discount) /* discard unused statement_discount */
        total_stmts_discounted -= statement_discount;
    store_attrib_sv(aTHX_ attr_hv, STR_WITH_LEN("total_stmts_measured"),   newSVnv(total_stmts_measured));
    store_attrib_sv(aTHX_ attr_hv, STR_WITH_LEN("total_stmts_discounted"), newSVnv(total_stmts_discounted));
    store_attrib_sv(aTHX_ attr_hv, STR_WITH_LEN("total_stmts_duration"),   newSVnv(total_stmts_duration));
    store_attrib_sv(aTHX_ attr_hv, STR_WITH_LEN("total_sub_calls"),        newSVnv(total_sub_calls));

    if (1) {
        int show_summary_stats = (trace_level >= 1);

        if (profiler_end_time && total_stmts_duration > profiler_duration * 1.1) {
            logwarn("The sum of the statement timings is %.1"NVff"%% of the total time profiling."
                 " (Values slightly over 100%% can be due simply to cumulative timing errors,"
                 " whereas larger values can indicate a problem with the clock used.)\n",
                total_stmts_duration / profiler_duration * 100);
            show_summary_stats = 1;
        }

        if (show_summary_stats)
            logwarn("Summary: statements profiled %d (%d-%d), sum of time %"NVff"s, profile spanned %"NVff"s\n",
                total_stmts_measured-total_stmts_discounted,
                total_stmts_measured, total_stmts_discounted,
                total_stmts_duration, profiler_end_time-profiler_start_time);
    }

    profile_hv = newHV();
    (void)hv_stores(profile_hv, "attribute",          newRV_noinc((SV*)attr_hv));
    (void)hv_stores(profile_hv, "fid_fileinfo",       newRV_noinc((SV*)fid_fileinfo_av));
    (void)hv_stores(profile_hv, "fid_srclines",   newRV_noinc((SV*)fid_srclines_av));
    (void)hv_stores(profile_hv, "fid_line_time",      newRV_noinc((SV*)fid_line_time_av));
    (void)hv_stores(profile_modes, "fid_line_time", newSVpvs("line"));
    if (fid_block_time_av) {
        (void)hv_stores(profile_hv, "fid_block_time",      newRV_noinc((SV*)fid_block_time_av));
        (void)hv_stores(profile_modes, "fid_block_time", newSVpvs("block"));
    }
    if (fid_sub_time_av) {
        (void)hv_stores(profile_hv, "fid_sub_time",    newRV_noinc((SV*)fid_sub_time_av));
        (void)hv_stores(profile_modes, "fid_sub_time", newSVpvs("sub"));
    }
    (void)hv_stores(profile_hv, "sub_subinfo",      newRV_noinc((SV*)sub_subinfo_hv));
    (void)hv_stores(profile_hv, "profile_modes",    newRV_noinc((SV*)profile_modes));
    return profile_hv;
}


/***********************************
 * Perl XS Code Below Here         *
 ***********************************/

MODULE = Devel::NYTProf     PACKAGE = Devel::NYTProf::Constants

PROTOTYPES: DISABLE

BOOT:
    {
    HV *stash = gv_stashpv("Devel::NYTProf::Constants", GV_ADDWARN);
    /* NYTP_FIDf_* */
    newCONSTSUB(stash, "NYTP_FIDf_IS_PMC",       newSViv(NYTP_FIDf_IS_PMC));
    newCONSTSUB(stash, "NYTP_FIDf_VIA_STMT",     newSViv(NYTP_FIDf_VIA_STMT));
    newCONSTSUB(stash, "NYTP_FIDf_VIA_SUB",      newSViv(NYTP_FIDf_VIA_SUB));
    newCONSTSUB(stash, "NYTP_FIDf_IS_AUTOSPLIT", newSViv(NYTP_FIDf_IS_AUTOSPLIT));
    newCONSTSUB(stash, "NYTP_FIDf_HAS_SRC",      newSViv(NYTP_FIDf_HAS_SRC));
    newCONSTSUB(stash, "NYTP_FIDf_SAVE_SRC",     newSViv(NYTP_FIDf_SAVE_SRC));
    newCONSTSUB(stash, "NYTP_FIDf_IS_ALIAS",     newSViv(NYTP_FIDf_IS_ALIAS));
    newCONSTSUB(stash, "NYTP_FIDf_IS_FAKE",      newSViv(NYTP_FIDf_IS_FAKE));
    /* NYTP_FIDi_* */
    newCONSTSUB(stash, "NYTP_FIDi_FILENAME",  newSViv(NYTP_FIDi_FILENAME));
    newCONSTSUB(stash, "NYTP_FIDi_EVAL_FID",  newSViv(NYTP_FIDi_EVAL_FID));
    newCONSTSUB(stash, "NYTP_FIDi_EVAL_LINE", newSViv(NYTP_FIDi_EVAL_LINE));
    newCONSTSUB(stash, "NYTP_FIDi_FID",       newSViv(NYTP_FIDi_FID));
    newCONSTSUB(stash, "NYTP_FIDi_FLAGS",     newSViv(NYTP_FIDi_FLAGS));
    newCONSTSUB(stash, "NYTP_FIDi_FILESIZE",  newSViv(NYTP_FIDi_FILESIZE));
    newCONSTSUB(stash, "NYTP_FIDi_FILEMTIME", newSViv(NYTP_FIDi_FILEMTIME));
    newCONSTSUB(stash, "NYTP_FIDi_PROFILE",   newSViv(NYTP_FIDi_PROFILE));
    newCONSTSUB(stash, "NYTP_FIDi_EVAL_FI",   newSViv(NYTP_FIDi_EVAL_FI));
    newCONSTSUB(stash, "NYTP_FIDi_HAS_EVALS", newSViv(NYTP_FIDi_HAS_EVALS));
    newCONSTSUB(stash, "NYTP_FIDi_SUBS_DEFINED", newSViv(NYTP_FIDi_SUBS_DEFINED));
    newCONSTSUB(stash, "NYTP_FIDi_SUBS_CALLED",  newSViv(NYTP_FIDi_SUBS_CALLED));
    /* NYTP_SIi_* */
    newCONSTSUB(stash, "NYTP_SIi_FID",          newSViv(NYTP_SIi_FID));
    newCONSTSUB(stash, "NYTP_SIi_FIRST_LINE",   newSViv(NYTP_SIi_FIRST_LINE));
    newCONSTSUB(stash, "NYTP_SIi_LAST_LINE",    newSViv(NYTP_SIi_LAST_LINE));
    newCONSTSUB(stash, "NYTP_SIi_CALL_COUNT",   newSViv(NYTP_SIi_CALL_COUNT));
    newCONSTSUB(stash, "NYTP_SIi_INCL_RTIME",   newSViv(NYTP_SIi_INCL_RTIME));
    newCONSTSUB(stash, "NYTP_SIi_EXCL_RTIME",   newSViv(NYTP_SIi_EXCL_RTIME));
    newCONSTSUB(stash, "NYTP_SIi_SUB_NAME",     newSViv(NYTP_SIi_SUB_NAME));
    newCONSTSUB(stash, "NYTP_SIi_PROFILE",      newSViv(NYTP_SIi_PROFILE));
    newCONSTSUB(stash, "NYTP_SIi_REC_DEPTH",    newSViv(NYTP_SIi_REC_DEPTH));
    newCONSTSUB(stash, "NYTP_SIi_RECI_RTIME",   newSViv(NYTP_SIi_RECI_RTIME));
    newCONSTSUB(stash, "NYTP_SIi_CALLED_BY",    newSViv(NYTP_SIi_CALLED_BY));
    /* NYTP_SCi_* */
    newCONSTSUB(stash, "NYTP_SCi_CALL_COUNT",   newSViv(NYTP_SCi_CALL_COUNT));
    newCONSTSUB(stash, "NYTP_SCi_INCL_RTIME",   newSViv(NYTP_SCi_INCL_RTIME));
    newCONSTSUB(stash, "NYTP_SCi_EXCL_RTIME",   newSViv(NYTP_SCi_EXCL_RTIME));
    newCONSTSUB(stash, "NYTP_SCi_RECI_RTIME",   newSViv(NYTP_SCi_RECI_RTIME));
    newCONSTSUB(stash, "NYTP_SCi_REC_DEPTH",    newSViv(NYTP_SCi_REC_DEPTH));
    newCONSTSUB(stash, "NYTP_SCi_CALLING_SUB",  newSViv(NYTP_SCi_CALLING_SUB));
    /* others */
    newCONSTSUB(stash, "NYTP_DEFAULT_COMPRESSION", newSViv(default_compression_level));
    newCONSTSUB(stash, "NYTP_FILE_MAJOR_VERSION",  newSViv(NYTP_FILE_MAJOR_VERSION));
    newCONSTSUB(stash, "NYTP_FILE_MINOR_VERSION",  newSViv(NYTP_FILE_MINOR_VERSION));
    newCONSTSUB(stash, "NYTP_ZLIB_VERSION",     newSVpv(ZLIB_VERSION, 0));
}


MODULE = Devel::NYTProf     PACKAGE = Devel::NYTProf::Test

PROTOTYPES: DISABLE

void
example_xsub(const char *unused="", SV *action=Nullsv, SV *arg=Nullsv)
    CODE:
    if (!action)
        XSRETURN(0);
    if (SvROK(action) && SvTYPE(SvRV(action))==SVt_PVCV) {
        /* perl <= 5.8.8 doesn't use OP_ENTERSUB so won't be seen by NYTProf */
        PUSHMARK(SP);
        call_sv(action, G_VOID|G_DISCARD);
    }
    else if (strEQ(SvPV_nolen(action),"eval"))
        eval_pv(SvPV_nolen(arg), TRUE);
    else if (strEQ(SvPV_nolen(action),"die"))
        croak("example_xsub(die)");
    logwarn("example_xsub: unknown action '%s'\n", SvPV_nolen(action));

void
example_xsub_eval(...)
    CODE:
    PERL_UNUSED_VAR(items);
    /* to enable testing of string evals in embedded environments
     * where there's no caller file information available.
     * Only it doesn't actually do that because perl knows
     * what it's executing at the time eval_pv() gets called.
     * We need a better test, closer to true embedded.
     */
    eval_pv("Devel::NYTProf::Test::example_xsub()", 1);


MODULE = Devel::NYTProf     PACKAGE = DB

PROTOTYPES: DISABLE

void
DB_profiler(...)
CODE:
    /* this sub gets aliased as "DB::DB" by NYTProf.pm if use_db_sub is true */
    PERL_UNUSED_VAR(items);
    if (opt_use_db_sub)
        DB_stmt(aTHX_ NULL, PL_op);
    else if (1||trace_level)
        logwarn("DB called needlessly\n");

void
set_option(const char *opt, const char *value)
    C_ARGS:
    aTHX_ opt, value

int
init_profiler()
    C_ARGS:
    aTHX

int
enable_profile(char *file = NULL)
    C_ARGS:
    aTHX_ file
    POSTCALL:
    /* if profiler was previously disabled */
    /* then arrange for the enable_profile call to be noted */
    if (!RETVAL) {
        DB_stmt(aTHX_ PL_curcop, PL_op);
    }


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
    INIT:
    PERL_UNUSED_ARG(ix);
    PERL_UNUSED_ARG(items);

void
_INIT()
    CODE:
    if (profile_start == NYTP_START_INIT)  {
        enable_profile(aTHX_ NULL);
    }
    else if (profile_start == NYTP_START_END) {
        SV *enable_profile_sv = (SV *)get_cv("DB::enable_profile", GV_ADDWARN);
        if (trace_level >= 2)
            logwarn("~ enable_profile defered until END\n");
        av_unshift(PL_endav, 1);  /* we want to be first */
        av_store(PL_endav, 0, SvREFCNT_inc(enable_profile_sv));
    }
    /* we want to END { finish_profile() } but we want it to be the last END
     * block run so we don't push it into PL_endav until INIT phase.
     * so it's likely to be the last thing run.
     */
    av_push(PL_endav, (SV *)get_cv("DB::finish_profile", GV_ADDWARN));
    if (trace_level >= 2)
        logwarn("~ INIT done\n");



MODULE = Devel::NYTProf     PACKAGE = Devel::NYTProf::Data

PROTOTYPES: DISABLE

HV*
load_profile_data_from_file(file,cb=NULL)
char *file;
SV* cb;
    PREINIT:
    int result;
    CODE:
    if (trace_level)
        logwarn("reading profile data from file %s\n", file);
    in = NYTP_open(file, "rb");
    if (in == NULL) {
        croak("Failed to open input '%s': %s", file, strerror(errno));
    }
    RETVAL = load_profile_data_from_stream(cb);
    if ((result = NYTP_close(in, 0)))
        logwarn("Error closing profile data file: %s\n", strerror(result));
    OUTPUT:
    RETVAL
