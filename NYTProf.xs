/* vim: ts=8 sw=4 expandtab:
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
#ifndef WIN32
#define PERL_NO_GET_CONTEXT                       /* we want efficiency */
#endif

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#ifndef NO_PPPORT_H
#   include "ppport.h"
#endif

#if !defined(OutCopFILE)
#    define OutCopFILE CopFILE
#endif
#ifndef gv_fetchfile_flags
#define gv_fetchfile_flags(str, len, flags) gv_fetchfile(str)
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

#if (PERL_VERSION < 8) || ((PERL_VERSION == 8) && (PERL_SUBVERSION < 8))
/* If we're using DB::DB() instead of opcode redirection with an old perl
 * then PL_curcop in DB() will refer to the DB() wrapper in Devel/NYTProf.pm
 * so we'd have to crawl the stack to find the right cop. However, for some
 * reason that I don't pretend to understand the following expression works:
 */
#define PL_curcop_nytprof (use_db_sub ? ((cxstack + cxstack_ix)->blk_oldcop) : PL_curcop)
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

#define NYTP_TAG_ATTRIBUTE       ':'    /* :name=value\n */
#define NYTP_TAG_COMMENT         '#'    /* till newline */
#define NYTP_TAG_TIME_BLOCK      '*'
#define NYTP_TAG_TIME_LINE       '+'
#define NYTP_TAG_DISCOUNT        '-'
#define NYTP_TAG_NEW_FID         '@'
#define NYTP_TAG_SRC_LINE        'S'    /* fid, line, str */
#define NYTP_TAG_SUB_LINE_RANGE  's'
#define NYTP_TAG_SUB_CALLERS     'c'
#define NYTP_TAG_PID_START       'P'
#define NYTP_TAG_PID_END         'p'
#define NYTP_TAG_STRING          '\'' 
#define NYTP_TAG_STRING_UTF8     '"' 
#define NYTP_TAG_START_DEFLATE   'z' 
#define NYTP_TAG_NO_TAG          '\0'   /* Used as a flag to mean "no tag" */

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
#define NYTP_SCi_INCL_UTIME  3   /* incl user cpu time in sub */
#define NYTP_SCi_INCL_STIME  4   /* incl sys  cpu time in sub */
#define NYTP_SCi_RECI_RTIME  5   /* recursive incl real time in sub */
#define NYTP_SCi_REC_DEPTH   6   /* max recursion call depth */
#define NYTP_SCi_CALLING_SUB 7   /* name of calling sub */
#define NYTP_SCi_elements    8   /* highest index, plus 1 */

/* Hash table definitions */
#define MAX_HASH_SIZE 512

static int next_fid = 1;         /* 0 is reserved */

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

#define NYTP_FILE_STDIO         0
#define NYTP_FILE_DEFLATE       1
#define NYTP_FILE_INFLATE       2

#define NYTP_FILE_SMALL_BUFFER_SIZE   4096
#define NYTP_FILE_LARGE_BUFFER_SIZE   16384

#ifdef HAS_ZLIB
#  define FILE_STATE(f)         ((f)->state)
#else
#  define FILE_STATE(f)         NYTP_FILE_STDIO
#endif

typedef struct {
    FILE *file;
#ifdef HAS_ZLIB
    unsigned char state;
    bool stdio_at_eof;
    bool zlib_at_eof;
    /* For input only, the position we are in large_buffer.  */
    unsigned int count;
    z_stream zs;
    unsigned char small_buffer[NYTP_FILE_SMALL_BUFFER_SIZE];
    unsigned char large_buffer[NYTP_FILE_LARGE_BUFFER_SIZE];
#endif
} NYTP_file_t;

typedef NYTP_file_t *NYTP_file;

static int NYTP_eof(NYTP_file ifile);
static const char * NYTP_fstrerror(NYTP_file file);

/* defaults */
static NYTP_file out;
static NYTP_file in;

/* options and overrides */
static char PROF_output_file[MAXPATHLEN+1] = "nytprof.out";
static unsigned int profile_opts = NYTP_OPTf_OPTIMIZE;
static int profile_start = NYTP_START_BEGIN;      /* when to start profiling */
static int profile_zero = 0;                      /* don't do timing, all times are zero */

struct NYTP_int_options_t {
  const char *option_name;
  int option_value;
};

/* XXX boolean options should be moved into profile_opts */
static struct NYTP_int_options_t options[] = {
#define usecputime options[0].option_value
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
#define use_db_sub options[6].option_value
    { "use_db_sub", 0 },
#define compression_level options[7].option_value
    { "compress", default_compression_level },
#define profile_clock options[8].option_value
    { "clock", -1 },
#define profile_stmts options[9].option_value
    { "stmts", 1 },                              /* statement exclusive times */
#define profile_sysops options[10].option_value
    { "sysops", 0 }                              /* opcodes that make slow system calls */
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
#  define get_time_of_day(into) if (!profile_zero) CLOCK_GETTIME(&into)
#  define get_ticks_between(s, e, ticks, overflow) STMT_START { \
    overflow = 0; \
    ticks = ((e.tv_sec - s.tv_sec) * CLOCKS_PER_TICK + (e.tv_nsec / 100) - (s.tv_nsec / 100)); \
} STMT_END

#else                                             /* !HAS_CLOCK_GETTIME */

#ifdef HAS_GETTIMEOFDAY
typedef struct timeval time_of_day_t;
#  define CLOCKS_PER_TICK 1000000                 /* 1 million */
#  define get_time_of_day(into) if (!profile_zero) gettimeofday(&into, NULL)
#  define get_ticks_between(s, e, ticks, overflow) STMT_START { \
    overflow = 0; \
    ticks = ((e.tv_sec - s.tv_sec) * CLOCKS_PER_TICK + e.tv_usec - s.tv_usec); \
} STMT_END
#else
static int (*u2time)(pTHX_ UV *) = 0;
typedef UV time_of_day_t[2];
#  define CLOCKS_PER_TICK 1000000                 /* 1 million */
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
static unsigned int is_profiling;       /* disable_profile() & enable_profile() */
static Pid_t last_pid;
static NV cumulative_overhead_ticks = 0.0;
static NV cumulative_subr_secs = 0.0;
static UV cumulative_subr_seqn = 0;

static unsigned int ticks_per_sec = 0;            /* 0 forces error if not set */

/* prototypes */
static void output_header(pTHX);
static void output_tag_int(unsigned char tag, unsigned int);
#define     output_int(i)   output_tag_int(NYTP_TAG_NO_TAG, (unsigned int)(i))
static void output_str(char *str, I32 len);
static void output_nv(NV nv);
static unsigned int read_int(void);
static SV *read_str(pTHX_ SV *sv);
static unsigned int get_file_id(pTHX_ char*, STRLEN, int created_via);
static void DB_stmt(pTHX_ COP *cop, OP *op);
static void set_option(pTHX_ const char*, const char*);
static int enable_profile(pTHX_ char *file);
static int disable_profile(pTHX);
static void finish_profile(pTHX);
static void open_output_file(pTHX_ char *);
static int reinit_if_forked(pTHX);
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

static void
logwarn(const char *pat, ...)
    __attribute__format__(__printf__,1,2)
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

/* XXX The proper return value would be Off_t */
static long
NYTP_tell(NYTP_file file) {
#ifdef HAS_ZLIB
    /* This has to work with compressed files as it's used in the croaking
       routine.  */
    if (FILE_STATE(file) != NYTP_FILE_STDIO) {
        return FILE_STATE(file) == NYTP_FILE_INFLATE
            ? file->zs.total_out : file->zs.total_in;
    }
#endif
    return (long)ftell(file->file);
}

static const char *
NYTP_type_of_offset(NYTP_file file) {
    switch (FILE_STATE(file)) {
    case NYTP_FILE_STDIO:
        return "";
    case NYTP_FILE_DEFLATE:
        return " in compressed output data";
        break;
    case NYTP_FILE_INFLATE:
        return " in compressed input data";
        break;
    default:
        return Perl_form_nocontext(" in stream in unknown state %d",
                                   FILE_STATE(file));
    }
}

#ifdef HASATTRIBUTE_NORETURN
__attribute__noreturn__
#endif 
static void
compressed_io_croak(NYTP_file file, const char *function) {
    const char *what;

    switch (FILE_STATE(file)) {
    case NYTP_FILE_STDIO:
        what = "stdio";
        break;
    case NYTP_FILE_DEFLATE:
        what = "compressed output";
        break;
    case NYTP_FILE_INFLATE:
        what = "compressed input";
        break;
    default:
        croak("Can't use function %s() on a stream of type %d at offset %ld",
              function, FILE_STATE(file), NYTP_tell(file));
    }
    croak("Can't use function %s() on a %s stream at offset %ld", function,
          what, NYTP_tell(file));
}

#ifdef HAS_ZLIB
static void
NYTP_start_deflate(NYTP_file file) {
    int status;

    if (FILE_STATE(file) != NYTP_FILE_STDIO) {
        compressed_io_croak(in, "NYTP_start_deflate");
    }
    FILE_STATE(file) = NYTP_FILE_DEFLATE;
    file->zs.next_in = (Bytef *) file->large_buffer;
    file->zs.avail_in = 0;
    file->zs.next_out = (Bytef *) file->small_buffer;
    file->zs.avail_out = NYTP_FILE_SMALL_BUFFER_SIZE;
    file->zs.zalloc = (alloc_func) 0;
    file->zs.zfree = (free_func) 0;
    file->zs.opaque = 0;

    status = deflateInit2(&(file->zs), compression_level, Z_DEFLATED, 15,
                       9 /* memLevel */, Z_DEFAULT_STRATEGY);
    if (status != Z_OK) {
        croak("deflateInit2 failed, error %d (%s)", status, file->zs.msg);
    }
}

static void
NYTP_start_inflate(NYTP_file file) {
    int status;
    if (FILE_STATE(file) != NYTP_FILE_STDIO) {
        compressed_io_croak(in, "NYTP_start_inflate");
    }
    FILE_STATE(file) = NYTP_FILE_INFLATE;

    file->zs.next_in = (Bytef *) file->small_buffer;
    file->zs.avail_in = 0;
    file->zs.next_out = (Bytef *) file->large_buffer;
    file->zs.avail_out = NYTP_FILE_LARGE_BUFFER_SIZE;
    file->zs.zalloc = (alloc_func) 0;
    file->zs.zfree = (free_func) 0;
    file->zs.opaque = 0;

    status = inflateInit2(&(file->zs), 15);
    if (status != Z_OK) {
        croak("inflateInit2 failed, error %d (%s)", status, file->zs.msg);
    }
}
#endif

static NYTP_file_t *
NYTP_open(const char *name, const char *mode) {
    FILE *raw_file = fopen(name, mode);
    NYTP_file file;

    if (!raw_file)
        return NULL;

    Newx(file, 1, NYTP_file_t);
    file->file = raw_file;

#ifdef HAS_ZLIB
    file->state = NYTP_FILE_STDIO;
    file->count = 0;
    file->stdio_at_eof = FALSE;
    file->zlib_at_eof = FALSE;

    file->zs.msg = "[Oops. zlib hasn't updated this error string]";
#endif

    return file;
}

static char *
NYTP_gets(NYTP_file ifile, char *buffer, unsigned int len) {
    if (FILE_STATE(ifile) != NYTP_FILE_STDIO) {
        compressed_io_croak(ifile, "NYTP_gets");
    }

    return fgets(buffer, len, ifile->file);
}

#ifdef HAS_ZLIB

static void
grab_input(NYTP_file ifile) {
    ifile->count = 0;
    ifile->zs.next_out = (Bytef *) ifile->large_buffer;
    ifile->zs.avail_out = NYTP_FILE_LARGE_BUFFER_SIZE;

#ifdef DEBUG_INFLATE
    fprintf(stderr, "grab_input enter\n");
#endif

    while (1) {
        int status;

        if (ifile->zs.avail_in == 0 && !ifile->stdio_at_eof) {
            size_t got = fread(ifile->small_buffer, 1,
                               NYTP_FILE_SMALL_BUFFER_SIZE, ifile->file);

            if (got == 0) {
                if (!feof(ifile->file)) {
                    dTHX;
                    croak("grab_input failed: %d (%s)", errno, strerror(errno));
                }
                ifile->stdio_at_eof = TRUE;
            }

            ifile->zs.avail_in = got;
            ifile->zs.next_in = (Bytef *) ifile->small_buffer;
        }

#ifdef DEBUG_INFLATE
        fprintf(stderr, "grab_input predef  next_in= %p avail_in= %08x\n"
                        "                   next_out=%p avail_out=%08x"
                " eof=%d,%d\n", ifile->zs.next_in, ifile->zs.avail_in,
                ifile->zs.next_out, ifile->zs.avail_out, ifile->stdio_at_eof,
                ifile->zlib_at_eof);
#endif

        status = inflate(&(ifile->zs), Z_NO_FLUSH);

#ifdef DEBUG_INFLATE
        fprintf(stderr, "grab_input postdef next_in= %p avail_in= %08x\n"
                        "                   next_out=%p avail_out=%08x "
                "status=%d\n", ifile->zs.next_in, ifile->zs.avail_in,
                ifile->zs.next_out, ifile->zs.avail_out, status);
#endif

        if (!(status == Z_OK || status == Z_STREAM_END)) {
            if (ifile->stdio_at_eof)
                croak("inflate failed, error %d (%s) at end of input file - is"
                      " it truncated?", status, ifile->zs.msg);
            croak("inflate failed, error %d (%s) at offset %ld in input file",
                  status, ifile->zs.msg, (long)ftell(ifile->file));
        }

        if (ifile->zs.avail_out == 0 || status == Z_STREAM_END) {
            if (status == Z_STREAM_END) {
                ifile->zlib_at_eof = TRUE;
            }
            return;
        }
    }
}

#endif


static size_t
NYTP_read_unchecked(NYTP_file ifile, void *buffer, size_t len) {
#ifdef HAS_ZLIB
    size_t result = 0;
#endif
    if (FILE_STATE(ifile) == NYTP_FILE_STDIO) {
        return fread(buffer, 1, len, ifile->file);
    }
    else if (FILE_STATE(ifile) != NYTP_FILE_INFLATE) {
        compressed_io_croak(ifile, "NYTP_read");
        return 0;
    }
#ifdef HAS_ZLIB
    while (1) {
        unsigned char *p = ifile->large_buffer + ifile->count;
        unsigned int remaining = ((unsigned char *) ifile->zs.next_out) - p;

        if (remaining >= len) {
            Copy(p, buffer, len, unsigned char);
            ifile->count += len;
            result += len;
            return result;
        }
        Copy(p, buffer, remaining, unsigned char);
        ifile->count = NYTP_FILE_LARGE_BUFFER_SIZE;
        result += remaining;
        len -= remaining;
        buffer = (void *)(remaining + (char *)buffer);
        if (ifile->zlib_at_eof)
            return result;
        grab_input(ifile);
    }
#endif
}


static size_t
NYTP_read(NYTP_file ifile, void *buffer, size_t len, const char *what) {
    size_t got = NYTP_read_unchecked(ifile, buffer, len);
    if (got != len) {
        croak("Profile format error whilst reading %s at %ld%s: expected %ld got %ld, %s",
              what, NYTP_tell(ifile), NYTP_type_of_offset(ifile), (long)len, (long)got,
                (NYTP_eof(in)) ? "end of file" : NYTP_fstrerror(in));
    }
    return len;
}


#ifdef HAS_ZLIB
/* Cheat, by telling zlib about a reduced amount of available output space,
   such that our next write of the (slightly underused) output buffer will
   align the underlying file pointer back with the size of our output buffer
   (and hopefully the underlying OS block writes).  */
static void
sync_avail_out_to_ftell(NYTP_file ofile) {
    const long result = ftell(ofile->file);
    const unsigned long where = result < 0 ? 0 : result;
    ofile->zs.avail_out =
        NYTP_FILE_SMALL_BUFFER_SIZE - where % NYTP_FILE_SMALL_BUFFER_SIZE;
#ifdef DEBUG_DEFLATE
    fprintf(stderr, "sync_avail_out_to_ftell pos=%ld, avail_out=%lu\n",
            result, (unsigned long) ofile->zs.avail_out);
#endif
}

/* flush has values as described for "allowed flush values" in zlib.h  */
static void
flush_output(NYTP_file ofile, int flush) {
    ofile->zs.next_in = (Bytef *) ofile->large_buffer;

#ifdef DEBUG_DEFLATE
    fprintf(stderr, "flush_output enter   flush = %d\n", flush);
#endif
    while (1) {
        int status;
#ifdef DEBUG_DEFLATE
        fprintf(stderr, "flush_output predef  next_in= %p avail_in= %08x\n"
                        "                     next_out=%p avail_out=%08x"
                " flush=%d\n", ofile->zs.next_in, ofile->zs.avail_in,
                ofile->zs.next_out, ofile->zs.avail_out, flush);
#endif
        status = deflate(&(ofile->zs), flush);

#ifdef DEBUG_DEFLATE
        fprintf(stderr, "flush_output postdef next_in= %p avail_in= %08x\n"
                        "                     next_out=%p avail_out=%08x "
                "status=%d\n", ofile->zs.next_in, ofile->zs.avail_in,
                ofile->zs.next_out, ofile->zs.avail_out, status);
#endif
      
        if (status == Z_OK || status == Z_STREAM_END) {
            if (ofile->zs.avail_out == 0 || flush != Z_NO_FLUSH) {
                int terminate
                    = ofile->zs.avail_in == 0 && ofile->zs.avail_out > 0;
                size_t avail = ((unsigned char *) ofile->zs.next_out)
                    - ofile->small_buffer;
                const unsigned char *where = ofile->small_buffer;

                while (avail > 0) {
                    size_t count = fwrite(where, 1, avail, ofile->file);

                    if (count > 0) {
                        where += count;
                        avail -= count;
                    } else {
                        dTHX;
                        croak("fwrite in flush error %d: %s", errno,
                              strerror(errno));
                    }
                }
                ofile->zs.next_out = (Bytef *) ofile->small_buffer;
                ofile->zs.avail_out = NYTP_FILE_SMALL_BUFFER_SIZE;
                if (terminate) {
                    ofile->zs.avail_in = 0;
                    if (flush == Z_SYNC_FLUSH) {
                        sync_avail_out_to_ftell(ofile);
                    }
                    return;
                }
            } else {
                ofile->zs.avail_in = 0;
                return;
            }
        } else {
            croak("deflate failed, error %d (%s) in %d", status, ofile->zs.msg,
                  getpid());
        }
    }
}
#endif

static size_t
NYTP_write(NYTP_file ofile, const void *buffer, size_t len) {
#ifdef HAS_ZLIB
    size_t result = 0;
#endif
    if (FILE_STATE(ofile) == NYTP_FILE_STDIO) {
        /* fwrite with len==0 is problematic */
        /* http://www.opengroup.org/platform/resolutions/bwg98-007.html */
        if (len == 0)
            return len;
        if (fwrite(buffer, 1, len, ofile->file) < 1) {
            dTHX;
            croak("fwrite error %d writing %ld bytes to fd%d: %s",
                errno, (long)len, fileno(ofile->file), strerror(errno));
        }
        return len;
    }
    else if (FILE_STATE(ofile) != NYTP_FILE_DEFLATE) {
        compressed_io_croak(ofile, "NYTP_write");
        return 0;
    }
#ifdef HAS_ZLIB
    while (1) {
        unsigned int remaining
            = NYTP_FILE_LARGE_BUFFER_SIZE - ofile->zs.avail_in;
        unsigned char *p = ofile->large_buffer + ofile->zs.avail_in;

        if (remaining >= len) {
            Copy(buffer, p, len, unsigned char);
            ofile->zs.avail_in += len;
            result += len;
            return result;
        } else {
            /* Copy what we can, then flush the buffer. Lather, rinse, repeat.
             */
            Copy(buffer, p, remaining, unsigned char);
            ofile->zs.avail_in = NYTP_FILE_LARGE_BUFFER_SIZE;
            result += remaining;
            len -= remaining;
            buffer = (void *)(remaining + (char *)buffer);
            flush_output(ofile, Z_NO_FLUSH);
        }
    }
#endif
}

static int
NYTP_printf(NYTP_file ofile, const char *format, ...) {
    int retval;
    va_list args;

    if (FILE_STATE(ofile) != NYTP_FILE_STDIO) {
        compressed_io_croak(ofile, "NYTP_printf");
    }

    va_start(args, format);
    retval = vfprintf(ofile->file, format, args);
    va_end(args);

    return retval;
}

static int
NYTP_flush(NYTP_file file) {
#ifdef HAS_ZLIB
    if (FILE_STATE(file) == NYTP_FILE_DEFLATE) {
        flush_output(file, Z_SYNC_FLUSH);
    }
#endif
    return fflush(file->file);
}

static int
NYTP_eof(NYTP_file ifile) {
#ifdef HAS_ZLIB
    if (FILE_STATE(ifile) == NYTP_FILE_INFLATE) {
        return ifile->zlib_at_eof;
    }
#endif
    return feof(ifile->file);
}

static const char *
NYTP_fstrerror(NYTP_file file) {
    dTHX;
#ifdef HAS_ZLIB
    if (FILE_STATE(file) == NYTP_FILE_DEFLATE || FILE_STATE(file) == NYTP_FILE_INFLATE) {
        return file->zs.msg;
    }
#endif
    return strerror(errno);
}

static int
NYTP_close(NYTP_file file, int discard) {
    FILE *raw_file = file->file;

#ifdef HAS_ZLIB
    if (!discard && FILE_STATE(file) == NYTP_FILE_DEFLATE) {
        const double ratio = file->zs.total_in / (double) file->zs.total_out;
        flush_output(file, Z_FINISH);
        fprintf(raw_file, "#\n"
                "# Total uncompressed bytes %lu\n"
                "# Total compressed bytes %lu\n"
                "# Compression ratio 1:%2f, data shrunk by %.2f%%\n",
                file->zs.total_in, file->zs.total_out, ratio,
                100 * (1 - 1 / ratio));
    }

    if (FILE_STATE(file) == NYTP_FILE_DEFLATE) {
        int status = deflateEnd(&(file->zs));
        if (status != Z_OK) {
            if (discard && status == Z_DATA_ERROR) {
                /* deflateEnd returns Z_OK if success, Z_STREAM_ERROR if the
                   stream state was inconsistent, Z_DATA_ERROR if the stream
                   was freed prematurely (some input or output was discarded).
                */
            } else {
                croak("deflateEnd failed, error %d (%s) in %d", status,
                      file->zs.msg, getpid());
            }
        }
    }
    else if (FILE_STATE(file) == NYTP_FILE_INFLATE) {
        int err = inflateEnd(&(file->zs));
        if (err != Z_OK) {
            croak("inflateEnd failed, error %d (%s)", err, file->zs.msg);
        }
    }
#endif

    Safefree(file);

    if (ferror(raw_file))
        logwarn("There was an error writing to the profile data file\n");

    if (discard) {
        /* close the underlying fd first so any buffered data gets discarded
         * when fclose is called below */
        close(fileno(raw_file));
    }

    return fclose(raw_file);
}


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
    SV *sv;
    time_t basetime = PL_basetime;

    assert(out != NULL);
    /* File header with "magic" string, with file major and minor version */
    NYTP_printf(out, "NYTProf %d %d\n", 3, 0);
    /* Human readable comments and attributes follow
     * comments start with '#', end with '\n', and are discarded
     * attributes start with ':', a word, '=', then the value, then '\n'
     */
    NYTP_printf(out, "# Perl profile database. Generated by Devel::NYTProf on %s",
        ctime(&basetime));                        /* uses \n from ctime to terminate line */

    /* XXX add options, $0, etc, but beware of embedded newlines */
    /* XXX would be good to adopt a proper charset & escaping for these */
    /* $^T */
    NYTP_printf(out, ":%s=%lu\n",      "basetime",      (unsigned long)PL_basetime);
    NYTP_printf(out, ":%s=%s\n",       "xs_version",    XS_VERSION);
    NYTP_printf(out, ":%s=%d.%d.%d\n", "perl_version",  PERL_REVISION, PERL_VERSION, PERL_SUBVERSION);
    NYTP_printf(out, ":%s=%d\n",       "clock_id",      profile_clock);
    NYTP_printf(out, ":%s=%u\n",       "ticks_per_sec", ticks_per_sec);
    NYTP_printf(out, ":%s=%lu\n",      "nv_size", (long unsigned int)sizeof(NV));
    /* $0 - application name */
    sv = get_sv("0",GV_ADDWARN);
    NYTP_printf(out, ":%s=%s\n",       "application", SvPV_nolen(sv));

#ifdef HAS_ZLIB
    if (compression_level) {
        const unsigned char tag = NYTP_TAG_START_DEFLATE;
        NYTP_printf(out, "# Compressed at level %d with zlib %s\n",
                    compression_level, zlibVersion());
        NYTP_write(out, &tag, sizeof(tag));
        NYTP_start_deflate(out);
    }
#endif
        
    output_tag_int(NYTP_TAG_PID_START, getpid());
    output_int(getppid());
    output_nv(gettimeofday_nv());

    write_cached_fids();                          /* empty initially, non-empty after fork */

    NYTP_flush(out);
}


static void
output_str(char *str, I32 len) {    /* negative len signifies utf8 */
    unsigned char tag = NYTP_TAG_STRING;
    if (len < 0) {
        tag = NYTP_TAG_STRING_UTF8;
        len = -len;
    }
    if (trace_level >= 10)
        logwarn("output_str('%.*s', %d)\n", len, str, len);
    output_tag_int(tag, len);
    NYTP_write(out, str, len);
}


static SV *
read_str(pTHX_ SV *sv) {
    STRLEN len;
    char *buf;
    unsigned char tag;

    NYTP_read(in, &tag, sizeof(tag), "string prefix");

    if (NYTP_TAG_STRING != tag && NYTP_TAG_STRING_UTF8 != tag)
        croak("File format error at offset %ld%s, expected string tag but found %d ('%c')",
              NYTP_tell(in)-1, NYTP_type_of_offset(in), tag, tag);

    len = read_int();
    if (sv) {
        SvGROW(sv, len+1);  /* forces SVt_PV */
    }
    else {
        sv = newSV(len+1); /* +1 to force SVt_PV even for 0 length string */
    }
    SvPOK_on(sv);

    buf = SvPV_nolen(sv);
    NYTP_read(in, buf, len, "string");
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
        strncpy(e->key, entry.key, e->key_len);

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
    output_tag_int(NYTP_TAG_NEW_FID, fid_info->id);
    output_int(fid_info->eval_fid);
    output_int(fid_info->eval_line_num);
    output_int(fid_info->fid_flags);
    output_int(fid_info->file_size);
    output_int(fid_info->file_mtime);

#ifdef WIN32
    /* Make sure we only use forward slashes in filenames */
    if (memchr(file_name, '\\', file_name_len)) {
        STRLEN i;
        char *file_name_copy = (char*)safemalloc(file_name_len);
        for (i=0; i<file_name_len; ++i) {
            char ch = file_name[i];
            file_name_copy[i] = ch == '\\' ? '/' : ch;
        }
        output_str(file_name_copy, (I32)file_name_len);
        Safefree(file_name_copy);
        return;
    }
#endif

    output_str(file_name, (I32)file_name_len);
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

    if (len > 3 && strnEQ(&file_name[len-3],".pm", len)) {
        /* ends in .pm, ok, does a newer .pmc exist? */
        /* based on doopen_pm() in perl's pp_ctl.c */
        SV *pmsv  = Perl_newSVpvn(aTHX_ file_name, len);
        SV *pmcsv = Perl_newSVpvf(aTHX_ "%s%c", SvPV_nolen(pmsv), 'c');
        Stat_t pmstat;
        Stat_t pmcstat;
        if (PerlLIO_lstat(SvPV_nolen(pmcsv), &pmcstat) == 0) {
            /* .pmc exists, is it newer than the .pm (if that exists) */
            if (PerlLIO_lstat(SvPV_nolen(pmsv), &pmstat) < 0 ||
            pmstat.st_mtime < pmcstat.st_mtime) {
                is_pmc = 1; /* hey, maybe it's Larry working on the perl6 comiler */
            }
        }
        SvREFCNT_dec(pmcsv);
        SvREFCNT_dec(pmsv);
    }

    return is_pmc;
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
    char *sep = "/";
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

    entry.key = file_name;
    entry.key_len = (unsigned int)file_name_len;

    /* inserted new entry */
    if (1 != hash_op(entry, &found, (bool)(created_via ? 1 : 0))) {
        if (trace_level >= 5) {
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
    if ('(' == file_name[0]) {
        if (']' == file_name[file_name_len-1]) {
            char *start = strchr(file_name, '[');
            const char *colon = ":";
            /* can't use strchr here (not nul terminated) so use rninstr */
            char *end = rninstr(file_name, file_name+file_name_len-1, colon, colon+1);

            if (!start || !end || start > end) {    /* should never happen */
                logwarn("NYTProf unsupported filename syntax '%s'\n", file_name);
                return 0;
            }
            ++start;                              /* move past [ */
            /* recurse */
            found->eval_fid = get_file_id(aTHX_ start, end - start, created_via);
            found->eval_line_num = atoi(end+1);
        }
        else if (strnEQ(file_name, "(eval ", 6)) {
            /* strange eval that doesn't have a filename associated */
            /* seen in mod_perl, possibly from eval_sv(sv) api call */
            char *eval_file = "/unknown-eval-invoker";
            found->eval_fid = get_file_id(aTHX_ eval_file, strlen(eval_file),
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
        !(file_name_len==1 && strEQ(file_name,"-" )) &&
        !(file_name_len==2 && strEQ(file_name,"-e")) &&
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
    || (found->key_len == 1 && strnEQ(found->key, "-",  1))
    || (found->key_len == 2 && strnEQ(found->key, "-e", 2))
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


/**
 * Output an integer in bytes, optionally preceded by a tag. Use the special tag
 * NYTP_TAG_NO_TAG to suppress the tag output. A wrapper macro output_int(i)
 * does this for you.
 * "In bytes" means output the number in binary, using the least number of bytes
 * possible.  All numbers are positive. Use sign slot as a marker
 */
static void
output_tag_int(unsigned char tag, unsigned int i)
{
    U8 buffer[6];
    U8 *p = buffer;

    if (tag != NYTP_TAG_NO_TAG)
        *p++ = tag;

    /* general case. handles all integers */
    if (i < 0x80) {                               /* < 8 bits */
        *p++ = (U8)i;
    }
    else if (i < 0x4000) {                        /* < 15 bits */
        *p++ = (U8)((i >> 8) | 0x80);
        *p++ = (U8)i;
    }
    else if (i < 0x200000) {                      /* < 22 bits */
        *p++ = (U8)((i >> 16) | 0xC0);
        *p++ = (U8)(i >> 8);
        *p++ = (U8)i;
    }
    else if (i < 0x10000000) {                    /* 32 bits */
        *p++ = (U8)((i >> 24) | 0xE0);
        *p++ = (U8)(i >> 16);
        *p++ = (U8)(i >> 8);
        *p++ = (U8)i;
    }
    else {                                        /* need all the bytes. */
        *p++ = 0xFF;
        *p++ = (U8)(i >> 24);
        *p++ = (U8)(i >> 16);
        *p++ = (U8)(i >> 8);
        *p++ = (U8)i;
    }
    NYTP_write(out, buffer, p - buffer);
}


static UV
output_uv_from_av(pTHX_ AV *av, int idx, UV default_uv)
{
    SV **svp = av_fetch(av, idx, 0);
    UV uv = (!svp || !SvOK(*svp)) ? default_uv : SvUV(*svp);
    output_int( uv );
    return uv;
}
        


/**
 * Output a double precision float via a simple binary write of the memory.
 * (Minor portbility issues are seen as less important than speed and space.)
 */
static void
output_nv(NV nv)
{
    NYTP_write(out, (unsigned char *)&nv, sizeof(NV));
}


static NV
output_nv_from_av(pTHX_ AV *av, int idx, NV default_nv)
{
    SV **svp = av_fetch(av, idx, 0);
    NV nv = (!svp || !SvOK(*svp)) ? default_nv : SvNV(*svp);
    output_nv( nv );
    return nv;
}
        

static const char* block_type[] =
{
    "NULL",
    "SUB",
    "EVAL",
    "LOOP",
    "SUBST",
    "BLOCK",
};

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
        case CXt_SUBST:                           /* FALLTHRU */
        case CXt_NULL:                            /* FALLTHRU */
        default:
            start_op = NULL;
            break;
    }
    if (!start_op) {
        if (trace_level >= trace)
            logwarn("\tstart_cop_of_context: can't find start of %s\n",
                block_type[CxTYPE(cx)]);
        return NULL;
    }
    /* find next cop from OP */
    o = start_op;
    while ( o && (type = (o->op_type) ? o->op_type : (int)o->op_targ) ) {
        if (type == OP_NEXTSTATE || type == OP_SETSTATE || type == OP_DBSTATE) {
            if (trace_level >= trace)
                logwarn("\tstart_cop_of_context %s is %s line %d of %s\n",
                    block_type[CxTYPE(cx)], OP_NAME(o), (int)CopLINE((COP*)o),
                    OutCopFILE((COP*)o));
            return (COP*)o;
        }
        /* should never get here but we do */
        if (trace_level >= trace) {
            logwarn("\tstart_cop_of_context %s op '%s' isn't a cop\n",
                block_type[CxTYPE(cx)], OP_NAME(o));
            if (trace_level >  trace)
                do_op_dump(1, PerlIO_stderr(), o);
        }
        o = o->op_next;
    }
    if (trace_level >= 3) {
        logwarn("\tstart_cop_of_context: can't find next cop for %s line %ld\n",
            block_type[CxTYPE(cx)], (long)CopLINE(PL_curcop_nytprof));
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
                    (int)top_si->si_type, top_si, top_si->si_prev, ccstack, top_si->si_cxstack);
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
                block_type[CxTYPE(cx)], (int)cxix, top_si->si_prev);
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
                block_type[CxTYPE(cx)], (sv) ? GvNAME(sv) : "");
            if (trace_level >= 9)
                sv_dump((SV*)cx->blk_sub.cv);
        }

        return 1;                                 /* stop looking */
    }

    /* NULL, EVAL, LOOP, SUBST, BLOCK context */
    if (trace_level >= 6)
        logwarn("\t%s\n", block_type[CxTYPE(cx)]);

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
                last_executed_line, block_type[CxTYPE(cx)],
                OutCopFILE(near_cop), OutCopFILE(PL_curcop_nytprof));
        return 1;                                 /* stop looking */
    }

    last_block_line = CopLINE(near_cop);
    if (trace_level >= 5)
        logwarn("\tat %d: block %d for %s\n",
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
static void
DB_stmt(pTHX_ COP *cop, OP *op)
{
    int saved_errno;
    char *file;
    long elapsed, overflow;

    if (!is_profiling || !profile_stmts) {
        return;
    }
    saved_errno = errno;

    if (usecputime) {
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
        logwarn("profile time overflow of %d seconds discarded\n", overflow);

    reinit_if_forked(aTHX);

    if (last_executed_fid) {

        output_tag_int((unsigned char)((profile_blocks)
                        ? NYTP_TAG_TIME_BLOCK : NYTP_TAG_TIME_LINE), elapsed);
        output_int(last_executed_fid);
        output_int(last_executed_line);
        if (profile_blocks) {
            output_int(last_block_line);
            output_int(last_sub_line);
        }
        if (trace_level >= 4)
            logwarn("Wrote %d:%-4d %2u ticks (%u, %u)\n", last_executed_fid,
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
            logwarn("NYTProf pid %ld: first statement line %d of %s\n",
                (long)getpid(), (int)CopLINE(cop), OutCopFILE(cop));
        }
    }
    if (file != last_executed_fileptr) { /* cache (hit ratio ~50% e.g. for perlcritic) */
        last_executed_fileptr = file;
        last_executed_fid = get_file_id(aTHX_ file, strlen(file), NYTP_FIDf_VIA_STMT);
    }

    if (trace_level >= 6)
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

    if (usecputime) {
        times(&start_ctime);
    }
    else {
        get_time_of_day(start_time);
    }

    /* measure time we've spent measuring so we can discount it */
    get_ticks_between(end_time, start_time, elapsed, overflow);
    cumulative_overhead_ticks += elapsed;

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
        else croak("NYTProf option begin has invalid value '%s'\n", value);
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
    else if (strEQ(option, "zero")) {
        profile_zero = atoi(value);
    }
    else {
        struct NYTP_int_options_t *opt_p = options;
        const struct NYTP_int_options_t *const opt_end
            = options + sizeof(options) / sizeof (struct NYTP_int_options_t);
        bool found = FALSE;
        do {
            if (strEQ(option, opt_p->option_name)) {
                opt_p->option_value = atoi(value);
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
    if (trace_level)
        logwarn("Opened %s\n", filename);

    output_header(aTHX);
}


static void
close_output_file(pTHX) {
    if (!out)
        return;

    write_src_of_files(aTHX);
    write_sub_line_ranges(aTHX);
    write_sub_callers(aTHX);
    /* mark end of profile data for last_pid pid
     * which is the pid that this file relates to
     */
    output_tag_int(NYTP_TAG_PID_END, last_pid);
    output_nv(gettimeofday_nv());

    if (-1 == NYTP_close(out, 0))
        logwarn("Error closing profile data file: %s\n", strerror(errno));
    out = NULL;
}


static int
reinit_if_forked(pTHX)
{
    if (getpid() == last_pid)
        return 0;                                 /* not forked */

    /* we're now the child process */
    if (trace_level >= 1)
        logwarn("New pid %d (was %d)\n", getpid(), last_pid);

    /* reset state */
    last_pid = getpid();
    last_executed_fileptr = NULL;
    last_executed_fid = 0; /* don't count the fork in the child */
    if (sub_callers_hv)
        hv_clear(sub_callers_hv);

    if (out) {
        /* any data that was unflushed in the parent when it forked
        * is now duplicated unflushed in this child process.
        * We need to be a little devious to prevent it getting flushed.
        */
        NYTP_close(out, 1); /* 1: discard output, to stop it being flushed to disk */

        open_output_file(aTHX_ PROF_output_file);
    }

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
    av_store(av, NYTP_SCi_INCL_UTIME, newSVnv(0.0));
    av_store(av, NYTP_SCi_INCL_STIME, newSVnv(0.0));
    /* NYTP_SCi_RECI_RTIME - allocated when needed */
    /* NYTP_SCi_REC_DEPTH  - allocated when needed */
    return av;
}

typedef struct subr_entry_st subr_entry_t;
struct subr_entry_st {
    int           completed;
    time_of_day_t initial_call_time;
    NV            initial_overhead_ticks;
    NV            initial_subr_secs;
    unsigned int  caller_fid;
    int           caller_line;
    CV           *caller_cv;
    SV           *caller_subname_sv;

    CV           *called_cv;
    int           called_cv_depth;
    char         *called_is_xs;         /* NULL, "xsub", or "syop" */
    SV           *called_subname_sv;
    CV *sub_cv;
    UV subr_call_seqn;
    char *stash_name;
    /* ensure all items are initialized in first phase of pp_subcall_profiler */
};


static void
subr_entry_destroy(pTHX_ subr_entry_t *subr_entry)
{
    if (subr_entry->caller_subname_sv) {
        sv_free(subr_entry->caller_subname_sv);
        subr_entry->caller_subname_sv = Nullsv;
    }
    if (subr_entry->called_subname_sv) {
        sv_free(subr_entry->called_subname_sv);
        subr_entry->called_subname_sv = Nullsv;
    }
}


static void
incr_sub_inclusive_time(pTHX_ subr_entry_t *subr_entry)
{
    int saved_errno = errno;
    char subr_call_key[500]; /* XXX */
    int subr_call_key_len;
    NV  overhead_ticks, called_sub_secs;
    SV *incl_time_sv, *excl_time_sv;
    NV  incl_subr_sec, excl_subr_sec;
    SV *sv_tmp;

    if (subr_entry->called_subname_sv == &PL_sv_undef) {
        logwarn("xsub/builtin exited via an exception (which isn't handled yet)\n");
        subr_entry->completed = 1;
    }

    /* For xsubs we get called both explicitly when the xsub returns, and by
     * the destructor. (That way if the xsub leaves via an exception then we'll
     * still get called, albeit a little later than we'd like.)
     */
    if (subr_entry->completed) {
        subr_entry_destroy(aTHX_ subr_entry);
        return;
    }
    subr_entry->completed = 1;

    /* statement overheads we've accumulated since we entered the sub */
    overhead_ticks = cumulative_overhead_ticks - subr_entry->initial_overhead_ticks;
    /* seconds spent in subroutines called by this subroutine */
    called_sub_secs = (cumulative_subr_secs - subr_entry->initial_subr_secs);

    if (profile_zero) {
        incl_subr_sec = 0.0;
        excl_subr_sec = 0.0;
    }
    else {
        time_of_day_t sub_end_time;
        long ticks, overflow;

        /* calculate ticks since we entered the sub */
        get_time_of_day(sub_end_time);
        get_ticks_between(subr_entry->initial_call_time, sub_end_time, ticks, overflow);
        
        incl_subr_sec = overflow + (ticks / (NV)ticks_per_sec);
        /* subtract statement measurement overheads */
        incl_subr_sec -= (overhead_ticks / ticks_per_sec);
        /* exclusive = inclusive - time spent in subroutines called by this subroutine */
        excl_subr_sec = incl_subr_sec - called_sub_secs;
    }

    subr_call_key_len = sprintf(subr_call_key, "%s[%u:%d]",
        SvPV_nolen(subr_entry->caller_subname_sv), subr_entry->caller_fid, subr_entry->caller_line);
    if (subr_call_key_len >= sizeof(subr_call_key))
        croak("panic: NYTProf buffer overflow on %s\n", subr_call_key);

    /* { called_subname => { "caller_subname[fid:line]" => [ count, incl_time, ... ] } } */
    sv_tmp = *hv_fetch(sub_callers_hv, SvPV_nolen(subr_entry->called_subname_sv),
        (I32)SvCUR(subr_entry->called_subname_sv), 1);

    if (!SvROK(sv_tmp)) { /* autoviv hash ref - is first call of this subname from anywhere */
        HV *hv = newHV();
        sv_setsv(sv_tmp, newRV_noinc((SV *)hv));

        if (subr_entry->called_is_xs) {
            /* create dummy item with fid=0 & line=0 to act as flag to indicate xs */
            AV *av = new_sub_call_info_av(aTHX);
            av_store(av, NYTP_SCi_CALL_COUNT, newSVuv(0));
            sv_setsv(*hv_fetch(hv, "[0:0]", 5, 1), newRV_noinc((SV *)av));

            if (   ('s' == *subr_entry->called_is_xs) /* "sop" (sysop) */
                || (subr_entry->called_cv && SvTYPE(subr_entry->called_cv) == SVt_PVCV)
            ) {
                /* We just use an empty string as the filename for xsubs
                    * because CvFILE() isn't reliable on perl 5.8.[78]
                    * and the name of the .c file isn't very useful anyway.
                    * The reader can try to associate the xsubs with the
                    * corresonding .pm file using the package part of the subname.
                    */
                SV *sv = *hv_fetch(GvHV(PL_DBsub), SvPV_nolen(subr_entry->called_subname_sv), (I32)SvCUR(subr_entry->called_subname_sv), 1);
                sv_setpv(sv, ":0-0"); /* empty file name */
                if (trace_level >= 2)
                    logwarn("Adding fake DBsub entry for '%s' xsub\n", SvPV_nolen(subr_entry->called_subname_sv));
            }
        }
    }

    /* drill-down to array of sub call information for this subr_call_key */
    sv_tmp = *hv_fetch((HV*)SvRV(sv_tmp), subr_call_key, subr_call_key_len, 1);
    AV *subr_call_av;
    if (!SvROK(sv_tmp)) { /* first call from this subname[fid:line] - autoviv array ref */
        subr_call_av = new_sub_call_info_av(aTHX);

        sv_setsv(sv_tmp, newRV_noinc((SV *)subr_call_av));

        if (subr_entry->stash_name) { /* note that a sub in this package was called */
            SV *pf_sv = *hv_fetch(pkg_fids_hv, subr_entry->stash_name, (I32)strlen(subr_entry->stash_name), 1);
            if (!SvOK(pf_sv)) { /* log when first created */
                if (trace_level >= 5)
                    logwarn("Noting that subs in package '%s' were called\n",
                        subr_entry->stash_name);
                sv_setsv(pf_sv, &PL_sv_no);
            }
        }
    }
    else {
        subr_call_av = (AV *)SvRV(sv_tmp);
        sv_inc(AvARRAY(subr_call_av)[NYTP_SCi_CALL_COUNT]);
    }

    if (trace_level >= 3)
        logwarn(" <-     %s %"NVff"s excl = %"NVff"s incl - %"NVff"s (%g-%g), oh %g-%g=%gt, d%d @%d:%d #%lu\n",
            SvPV_nolen(subr_entry->called_subname_sv),
            excl_subr_sec, incl_subr_sec, called_sub_secs,
            cumulative_subr_secs, subr_entry->initial_subr_secs,
            cumulative_overhead_ticks, subr_entry->initial_overhead_ticks, overhead_ticks,
            (int)subr_entry->called_cv_depth,
            subr_entry->caller_fid, subr_entry->caller_line, subr_entry->subr_call_seqn);

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


static void                                       /* wrapper called via scope exit due to save_destructor below */
incr_sub_inclusive_time_ix(pTHX_ void *save_ix_void)
{
    I32 save_ix = (I32)PTR2IV(save_ix_void);
    subr_entry_t *subr_entry = SSPTR(save_ix, subr_entry_t *);
    incr_sub_inclusive_time(aTHX_ subr_entry);
}


static SV *
resolve_sub(pTHX_ SV *sv, SV *subname_out_sv)
{
    GV *gv;
    HV *stash;
    CV *cv;

    /* copied from top of perl's pp_entersub */
    /* modified to return either CV or else a PV containing string to use */
    /* or a NULL in cases that pp_entersub would croak */
    switch (SvTYPE(sv)) {
        default:
            if (!SvROK(sv)) {
                char *sym;

                if (sv == &PL_sv_yes) {           /* unfound import, ignore */
                    if (subname_out_sv)
                        sv_setpvn(subname_out_sv, "import", 6);
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
            if (!(cv = GvCVu((GV*)sv)))
                cv = sv_2cv(sv, &stash, &gv, FALSE);
            if (!cv) {                            /* would autoload in this situation */
                if (subname_out_sv)
                    gv_efullname3(subname_out_sv, gv, Nullch);
                return NULL;
            }
            break;
    }
    return (SV *)cv;
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
    cx = &si->si_cxstack[ix];

    /* the common case of finding the caller on the same stack */
    if (CxTYPE(cx) == CXt_SUB || CxTYPE(cx) == CXt_FORMAT)
        return cx->blk_sub.cv;
    else if (CxTYPE(cx) == CXt_EVAL && cx->blk_eval.old_namesv) {
        return (CV*)&PL_sv_yes;     /* indicates a require */
    }
    else if (CxTYPE(cx) == CXt_EVAL && !CxTRYBLOCK(cx))
        return current_cv(aTHX_ ix - 1, si); /* recurse up stack */
    else if (ix == 0 && si->si_type == PERLSI_MAIN)
        return PL_main_cv;
    else if (ix > 0)
        return current_cv(aTHX_ ix - 1, si); /* recurse up stack */

    /* caller isn't on the same stack so we'll walk the stacks as well */
    if (si->si_type != PERLSI_MAIN) {
        return current_cv(aTHX_ si->si_prev->si_cxix, si->si_prev);
    }
    return Nullcv;
}


static OP *
pp_entersub_profiler(pTHX)
{
    return pp_subcall_profiler(aTHX_ 0);
}

static OP *
pp_sysop_profiler(pTHX)
{
    return pp_subcall_profiler(aTHX_ 1);
}

static OP *
pp_subcall_profiler(pTHX_ int is_sysop)
{
    OP *op;
    COP *prev_cop = PL_curcop;                    /* not PL_curcop_nytprof here */
    OP *next_op = PL_op->op_next;                 /* op to execute after sub returns */
    /* pp_entersub can be called with PL_op->op_type==0 */
    OPCODE op_type = (is_sysop) ? PL_op->op_type : OP_ENTERSUB;
    dSP;
    I32 save_ix;
    SV *sub_sv;
    subr_entry_t *subr_entry;
    int profile_sub_call = (profile_subs && is_profiling
        /* don't profile calls to non-existant import() methods */
        && !(op_type==OP_ENTERSUB && *SP == &PL_sv_yes)
    );

    if (profile_sub_call) {
        char *file;
        int saved_errno = errno;
        sub_sv = *SP;
        if (!profile_stmts)
            reinit_if_forked(aTHX);

        if (trace_level >= 99) {
            logwarn("entering sub\n");
            /* crude, but the only way to deal with the miriad logic at the
             * start of pp_entersub (which ought to be available as separate sub)
             */
            sv_dump(sub_sv);
        }

        /* allocate struct to save stack (very efficient) */
        /* XXX "warning: cast from pointer to integer of different size" with use64bitall=define */
        save_ix = SSNEWa(sizeof(*subr_entry), MEM_ALIGNBYTES);
        subr_entry = SSPTR(save_ix, subr_entry_t *);
        subr_entry->completed = 0;

        get_time_of_day(subr_entry->initial_call_time);
        subr_entry->initial_overhead_ticks = cumulative_overhead_ticks;
        subr_entry->initial_subr_secs      = cumulative_subr_secs;
        subr_entry->subr_call_seqn         = ++cumulative_subr_seqn;

        file = OutCopFILE(prev_cop);
        subr_entry->caller_fid = (file == last_executed_fileptr)
            ? last_executed_fid
            : get_file_id(aTHX_ file, strlen(file), NYTP_FIDf_VIA_SUB);
        subr_entry->caller_line = CopLINE(prev_cop);

        /* gather details about the caller */
        subr_entry->caller_cv = current_cv(aTHX_ cxstack_ix, NULL);
        subr_entry->caller_subname_sv = newSV(0); /* XXX add cache/stack thing for these SVs */
        if (subr_entry->caller_cv == PL_main_cv) {
            sv_setpvf(subr_entry->caller_subname_sv, "main::BEGIN");
        }
        else if (subr_entry->caller_cv == (CV*)&PL_sv_yes) { /* require */
            sv_setpvf(subr_entry->caller_subname_sv, "%s::%s", CopSTASHPV(PL_curcop), "BEGIN");
        }
        else {
            GV *gv = CvGV(subr_entry->caller_cv);
            if (gv) {
                gv_efullname3(subr_entry->caller_subname_sv, CvGV(subr_entry->caller_cv), Nullch);
            }
            else {
                logwarn("Can't determine name of calling sub (no GV) at %s line %d\n",
                    OutCopFILE(prev_cop), CopLINE(prev_cop));
                sv_dump((SV*)subr_entry->caller_cv);
                sv_setpv(subr_entry->caller_subname_sv, "__UNKNOWN__(NULLGV)");
            }
        }

        /* initialize items we'll set later */
        subr_entry->sub_cv = NULL;
        subr_entry->called_subname_sv = &PL_sv_undef; /* see incr_sub_inclusive_time */
        subr_entry->called_is_xs = "?"; /* we don't know yet */
        subr_entry->called_cv_depth = 0;

        SETERRNO(saved_errno, 0);
    }

    /*
     * For normal subs, pp_entersub enters the sub and returns the
     * first op *within* the sub (typically a nextstate/dbstate).
     * For XS subs, pp_entersub executes the entire sub
     * and returns the op *after* the sub (PL_op->op_next).
     * Other ops we profile (eg sysops) act like xsubs.
     * This call may exit via an exception, in which case the
     * block below doesn't get executed.
     */
    op = run_original_op(op_type);

    if (profile_sub_call) {
        int saved_errno = errno;

        SV *called_subname_sv;
        char *stash_name = NULL;
        CV *called_cv;
        char *is_xs;

        /* push a destructor hook onto the context stack to ensure we account
         * for time in the sub when we leave it, even if via an exception.
         */
        save_destructor_x(incr_sub_inclusive_time_ix, INT2PTR(void *, (IV)save_ix));


        called_subname_sv = newSV(0);
        if (is_sysop) {
            /* pretend builtins are xsubs in the same package
            * but with "CORE:" (one colon) prepended to the name.
            */
            const char *sysop_name = OP_NAME_safe(PL_op);
            called_cv = NULL;
            is_xs = "sop";
            if (profile_sysops == 1) { /* 1 == put sysops into 1 package */
                stash_name = "CORE";
                sv_setpvf(called_subname_sv, "%s::%s", stash_name, sysop_name);
            }
            else {                     /* 2 == put sysops into multiple packages */
                stash_name = CopSTASHPV(PL_curcop);
                sv_setpvf(called_subname_sv, "%s::CORE:%s", stash_name, sysop_name);
            }
            subr_entry->called_cv_depth = 1; /* an approximation for sysops */
        }
        else {
            if (op != next_op) {   /* have entered a sub */
                /* use cv of sub we've just entered to get name */
                called_cv = cxstack[cxstack_ix].blk_sub.cv;
                is_xs = NULL;
            }
            else {                 /* have returned from XS so use sub_sv for name */
                /* determine the original fully qualified name for sub */
                /* CV or NULL */
                called_cv = (CV *)resolve_sub(aTHX_ sub_sv, called_subname_sv);
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
                    sv_setpvf(called_subname_sv, "%s::%s", stash_name, GvNAME(gv));
                }
                else if (trace_level) {
                    logwarn("I'm confused about CV %p\n", called_cv);
                    /* looks like Class::MOP doesn't give the CV GV stash a name */
                    if (trace_level >= 2)
                        sv_dump((SV*)called_cv); /* coredumps in Perl_do_gvgv_dump, looks line GvXPVGV is false, presumably on a Class::MOP wierdo sub */
                }
            }

            if (!SvOK(called_subname_sv)) {

                if (!called_cv) {
                    /* should never get here as pp_entersub would have croaked */
                    const char *what = (is_xs) ? is_xs : "sub";
                    logwarn("unknown entersub %s '%s'\n", what, SvPV_nolen(sub_sv));
                    if (trace_level)
                        sv_dump(sub_sv);
                    sv_setpvf(called_subname_sv, "(unknown %s %s)", what, SvPV_nolen(sub_sv));
                }
                else {
                    /* unnamed CV, e.g. seen in mod_perl/Class::MOP. XXX do better? */
                    stash_name = HvNAME(CvSTASH(called_cv));
                    sv_setpvf(called_subname_sv, "%s::__UNKNOWN__[0x%p]",
                        (stash_name)?stash_name:"__UNKNOWN__", called_cv);
                    if (trace_level) {
                        logwarn("unknown entersub %s assumed to be anon called_cv '%s'\n",
                            (is_xs) ? is_xs : "sub", SvPV_nolen(sub_sv));
                        sv_dump(sub_sv);
                    }
                }
            }
            /* if called was xsub then we've already left it, so use depth+1 */
            subr_entry->called_cv_depth = (called_cv) ? CvDEPTH(called_cv)+(is_xs?1:0) : 0;
        }
        subr_entry->stash_name = stash_name;
        subr_entry->called_cv = called_cv;
        subr_entry->called_subname_sv = called_subname_sv;
        subr_entry->called_is_xs = is_xs;

        /* ignore our own DB::_INIT sub - only shows up with 5.8.9+ & 5.10.1+ */
        if (is_xs && SvCUR(called_subname_sv) == 9 && *SvPV_nolen(called_subname_sv) == 'D' && strEQ(SvPV_nolen(called_subname_sv), "DB::_INIT")) {
            subr_entry->completed = 1;
            goto skip_sub_profile;
        }
        /* catch profile_subs being turned off by disable_profile call */
        if (!profile_subs)
            subr_entry->completed = 1;

        if (trace_level >= 2) {
            logwarn(" ->%4s %s from %s (d%d, oh %"NVff"t, sub %"NVff"s) #%lu\n",
                (is_xs) ? is_xs : "sub", SvPV_nolen(subr_entry->called_subname_sv),
                SvPV_nolen(subr_entry->caller_subname_sv),
                subr_entry->called_cv_depth,
                subr_entry->initial_overhead_ticks,
                subr_entry->initial_subr_secs,
                subr_entry->subr_call_seqn
            );
        }

        if (is_xs) {
            /* for xsubs/builtins we've already left the sub, so end the timing now
             * rather than wait for the calling scope to get cleaned up.
             */
            incr_sub_inclusive_time(aTHX_ subr_entry);
        }

        skip_sub_profile:
        SETERRNO(saved_errno, 0);
    }

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

    if (trace_level)
        logwarn("NYTProf enable_profile (previously %s) to %s\n",
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
    if (use_db_sub)                 /* set PL_DBsingle if required */
        sv_setiv(PL_DBsingle, 1);

    /* discard time spent since profiler was disabled */
    get_time_of_day(start_time);

    return prev_is_profiling;
}


static int
disable_profile(pTHX)
{
    int prev_is_profiling = is_profiling;
    if (is_profiling) {
        if (use_db_sub)
            sv_setiv(PL_DBsingle, 0);
        if (out)
            NYTP_flush(out);
        is_profiling = 0;
    }
    if (trace_level)
        logwarn("NYTProf disable_profile (previously %s)\n",
            prev_is_profiling ? "enabled" : "disabled");
    return prev_is_profiling;
}


static void
finish_profile(pTHX)
{
    int saved_errno = errno;

    if (trace_level >= 1)
        logwarn("finish_profile (last_pid %d, getpid %d, overhead %"NVff"s, is_profiling %d)\n",
            last_pid, getpid(), cumulative_overhead_ticks/ticks_per_sec, is_profiling);

    /* write data for final statement, unless DB_leave has already */
    if (!profile_leave || use_db_sub)
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


/* Initial setup */
static int
init_profiler(pTHX)
{
#ifndef HAS_GETTIMEOFDAY
    SV **svp;
#endif

    /* Save the process id early. We monitor it to detect forks */
    last_pid = getpid();
    ticks_per_sec = (usecputime) ? CLOCKS_PER_SEC : CLOCKS_PER_TICK;

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
            logwarn("clock_gettime clock %d not available (%s) using CLOCK_REALTIME instead\n",
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

    if (profile_opts & NYTP_OPTf_OPTIMIZE)
         PL_perldb &= ~PERLDBf_NOOPT;
    else PL_perldb |=  PERLDBf_NOOPT;

    if (profile_opts & NYTP_OPTf_SAVESRC) {
        /* ask perl to keep the source lines so we can copy them */
        PL_perldb |= PERLDBf_SAVESRC | PERLDBf_SAVESRC_NOSUBS;
    }

    if (trace_level)
        logwarn("NYTProf init pid %d, clock %d%s\n", last_pid, profile_clock,
            profile_zero ? ", zero=1" : "");

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
        logwarn("Using Time::HiRes %p\n", u2time);
#endif

    /* create file id mapping hash */
    hashtable.table = (Hash_entry**)safemalloc(sizeof(Hash_entry*) * hashtable.size);
    memset(hashtable.table, 0, sizeof(Hash_entry*) * hashtable.size);

    open_output_file(aTHX_ PROF_output_file);

    /* redirect opcodes for statement profiling */
    Newxc(PL_ppaddr_orig, OP_max, void *, orig_ppaddr_t);
    Copy(PL_ppaddr, PL_ppaddr_orig, OP_max, void *);
    if (profile_stmts && !use_db_sub) {
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
            PL_ppaddr[OP_DUMP]       = pp_leave_profiler;
            PL_ppaddr[OP_RETURN]     = pp_leave_profiler;
            /* natural end of simple loop */
            PL_ppaddr[OP_UNSTACK]    = pp_leave_profiler;
            /* OP_NEXT is missing because that jumps to OP_UNSTACK */
            /* OP_EXIT and OP_EXEC need special handling */
            PL_ppaddr[OP_EXIT]       = pp_exit_profiler;
            PL_ppaddr[OP_EXEC]       = pp_exit_profiler;
        }
    }

    if (profile_sysops) {
        /* possible list of sys ops to profile:
            sysopen open close readline rcatline getc read
            print prtf sysread syswrite send recv
            eof tell seek sysseek readdir telldir seekdir rewinddir
            rand srand dbmopen dbmclose
            stat lstat readlink link unlink rename symlink truncate
            sselect select pipe_op bind connect listen accept shutdown
            ftatime ftblk ftchr ftctime ftdir fteexec fteowned fteread
            ftewrite ftfile ftis ftlink ftmtime ftpipe ftrexec ftrowned
            ftrread ftsgid ftsize ftsock ftsuid fttty ftzero ftrwrite ftsvtx
            fttext ftbinary custom
            ghbyname ghbyaddr ghostent shostent ehostent      -- hosts
            gnbyname gnbyaddr gnetent snetent enetent         -- networks
            gpbyname gpbynumber gprotoent sprotoent eprotoent -- protocols
            gsbyname gsbyport gservent sservent eservent      -- services
            gpwnam gpwuid gpwent spwent epwent getlogin       -- users
            ggrnam ggrgid ggrent sgrent egrent                -- groups
            open_dir closedir mkdir rmdir utime chmod chown fcntl
            backtick system fork wait waitpid glob
            msgget msgrcv msgsnd semget semop
            chdir flock ioctl sleep syscall dump chroot
            Perhaps make configurable. Could interate with Opcode module.
        */
        /* XXX this will turn into a loop over an array that maps
         * opcodes to the subname we'll use: OP_PRTF => "printf"
         */
        PL_ppaddr[OP_SLEEP] = pp_sysop_profiler;
        PL_ppaddr[OP_OPEN] = pp_sysop_profiler;
        PL_ppaddr[OP_CLOSE] = pp_sysop_profiler;
        PL_ppaddr[OP_READ] = pp_sysop_profiler;
        PL_ppaddr[OP_READLINE] = pp_sysop_profiler;
        PL_ppaddr[OP_STAT] = pp_sysop_profiler;
        PL_ppaddr[OP_OPEN_DIR] = pp_sysop_profiler;
        PL_ppaddr[OP_CLOSEDIR] = pp_sysop_profiler;
        PL_ppaddr[OP_READDIR] = pp_sysop_profiler;
        PL_ppaddr[OP_RAND] = pp_sysop_profiler;
        PL_ppaddr[OP_SRAND] = pp_sysop_profiler;
        PL_ppaddr[OP_WAIT] = pp_sysop_profiler;
        PL_ppaddr[OP_SELECT] = pp_sysop_profiler;
    }

    /* redirect opcodes for caller tracking */
    if (!sub_callers_hv)
        sub_callers_hv = newHV();
    if (!pkg_fids_hv)
        pkg_fids_hv = newHV();
    PL_ppaddr[OP_ENTERSUB] = pp_entersub_profiler;

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
    if (usecputime) {
        times(&start_ctime);
    }
    else {
        get_time_of_day(start_time);
    }
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
 */
static SV *
sub_pkg_filename_sv(pTHX_ char *sub_name)
{
    SV **svp;
    char *delim = "::";
    /* find end of package name */
    char *colon = rninstr(sub_name, sub_name+strlen(sub_name), delim, delim+2);
    if (!colon || colon == sub_name)
        return Nullsv;   /* no :: delimiter */
    svp = hv_fetch(pkg_fids_hv, sub_name, (I32)(colon-sub_name), 0);
    if (!svp)
        return Nullsv;   /* not a package we've profiled sub calls into */
    return *svp;
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
        logwarn("writing sub line ranges\n");

    /* Skim through PL_DBsub hash to build a package to filename hash
     * by associating the package part of the sub_name in the key
     * with the filename part of the value.
     * but only for packages we already know we're interested in
     */
    hv_iterinit(hv);
    while (NULL != (file_lines_sv = hv_iternextsv(hv, &sub_name, &sub_name_len))) {
        char *filename = SvPV_nolen(file_lines_sv);
        char *first = strrchr(filename, ':');
        STRLEN filename_len = (first) ? first - filename : 0;

        /* get sv for package-of-subname to filename mapping */
        SV *pkg_filename_sv = sub_pkg_filename_sv(aTHX_ sub_name);

        if (!pkg_filename_sv) /* we don't know package */
            continue;

        /* already got a filename for this package XXX should allow multiple */
        if (SvTRUE(pkg_filename_sv))
            continue;

        /* ignore if filename is empty (eg xs) */
        if (!filename_len) {
            if (trace_level >= 3)
                logwarn("Sub %.*s has no filename associated (%s)\n",
                    sub_name_len, sub_name, filename);
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

    /* Iterate over PL_DBsub writing out fid and source line range of subs.
     * If filename is missing (i.e., because it's an xsub so has no source file)
     * then use the filename of another sub in the same package.
     */
    while (NULL != (file_lines_sv = hv_iternextsv(hv, &sub_name, &sub_name_len))) {
        /* "filename:first-last" */
        char *filename = SvPV_nolen(file_lines_sv);
        char *first = strrchr(filename, ':');
        char *last = (first) ? strchr(first, '-') : NULL;
        STRLEN filename_len = first - filename;
        UV first_line, last_line;

        if (!first || !last || !grok_number(first+1, last-first-1, &first_line)) {
            logwarn("Can't parse %%DB::sub entry for %s '%s'\n", sub_name, filename);
            continue;
        }
        last_line = atoi(++last);

        if (0 &&!first_line && !last_line && strstr(sub_name, "::BEGIN"))
            continue;                             /* no point writing these XXX? */

        if (!filename_len) {    /* no filename, so presumably a fake entry for xsub */
            /* do we know a filename that contains subs in the same package */
            SV *pkg_filename_sv = sub_pkg_filename_sv(aTHX_ sub_name);
            if (pkg_filename_sv && SvTRUE(pkg_filename_sv)) {
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
                    sub_name, filename_len, filename);
            continue; /* no point in writing subs in files we've not profiled */
        }

        if (trace_level >= 2)
            logwarn("Sub %s fid %u lines %lu..%lu\n",
                sub_name, fid, (unsigned long)first_line, (unsigned long)last_line);

        output_tag_int(NYTP_TAG_SUB_LINE_RANGE, fid);
        output_int(first_line);
        output_int(last_line);
        output_str(sub_name, sub_name_len);
    }
}


static void
write_sub_callers(pTHX)
{
    char *called_subname;
    I32 called_subname_len;
    SV *fid_line_rvhv;

    if (!sub_callers_hv)
        return;
    if (trace_level >= 2)
        logwarn("writing sub callers\n");

    hv_iterinit(sub_callers_hv);
    while (NULL != (fid_line_rvhv = hv_iternextsv(sub_callers_hv, &called_subname, &called_subname_len))) {
        HV *fid_lines_hv = (HV*)SvRV(fid_line_rvhv);
        char *caller_subname;
        I32 caller_subname_len;
        SV *sv;

        /* I32 level, PerlIO *file, SV *sv, I32 nest, I32 maxnest, bool dumpops, STRLEN pvlim */
        if (0) do_sv_dump(0, Perl_debug_log, fid_line_rvhv, 0, 5, 0, 100);

        /* iterate over callers to this sub ({ "subname[fid:line]" => [ ... ] })  */
        hv_iterinit(fid_lines_hv);
        while (NULL != (sv = hv_iternextsv(fid_lines_hv, &caller_subname, &caller_subname_len))) {
            NV sc[NYTP_SCi_elements];
            AV *av = (AV *)SvRV(sv);
            int trace = (trace_level >= 3);

            unsigned int fid = 0, line = 0;
            char *fid_line_delim = "[";
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

            output_tag_int(NYTP_TAG_SUB_CALLERS, fid);
            output_str(caller_subname, caller_subname_len);
            output_int(line);
            sc[NYTP_SCi_CALL_COUNT] = output_uv_from_av(aTHX_ av, NYTP_SCi_CALL_COUNT, 0) * 1.0;
            sc[NYTP_SCi_INCL_RTIME] = output_nv_from_av(aTHX_ av, NYTP_SCi_INCL_RTIME, 0.0);
            sc[NYTP_SCi_EXCL_RTIME] = output_nv_from_av(aTHX_ av, NYTP_SCi_EXCL_RTIME, 0.0);
            sc[NYTP_SCi_INCL_UTIME] = output_nv_from_av(aTHX_ av, NYTP_SCi_INCL_UTIME, 0.0);
            sc[NYTP_SCi_INCL_STIME] = output_nv_from_av(aTHX_ av, NYTP_SCi_INCL_STIME, 0.0);
            sc[NYTP_SCi_RECI_RTIME] = output_nv_from_av(aTHX_ av, NYTP_SCi_RECI_RTIME, 0.0);
            sc[NYTP_SCi_REC_DEPTH]  = output_uv_from_av(aTHX_ av, NYTP_SCi_REC_DEPTH , 0) * 1.0;
            output_str(called_subname, called_subname_len);

            /* sanity check - early warning */
            if (sc[NYTP_SCi_INCL_RTIME] < 0.0 || sc[NYTP_SCi_EXCL_RTIME] < 0.0) {
                logwarn("%s call has negative time for call from %u:%d!\n",
                    called_subname, fid, line);
                trace = 1;
            }

            if (trace) {
                if (!fid && !line) {
                    logwarn("%s is xsub\n", called_subname);
                }
                else {
                    logwarn("%s called by %.*s at %u:%u: count %ld (i%"NVff"s e%"NVff"s u%"NVff"s s%"NVff"s, d%d ri%"NVff"s)\n",
                        called_subname,
                        caller_subname_len, caller_subname, fid, line, (long)sc[NYTP_SCi_CALL_COUNT],
                        sc[NYTP_SCi_INCL_RTIME], sc[NYTP_SCi_EXCL_RTIME],
                        sc[NYTP_SCi_INCL_UTIME], sc[NYTP_SCi_INCL_STIME],
                        (int)sc[NYTP_SCi_REC_DEPTH], sc[NYTP_SCi_RECI_RTIME]);
                }
            }
        }
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

    if (trace_level >= 1)
        logwarn("writing file source code\n");

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

        lines = av_len(src_av);
        if (trace_level >= 4)
            logwarn("fid %d has %ld src lines\n", e->id, (long)lines);
        /* for perl 5.10.0 or 5.8.8 (or earlier) use_db_sub is needed to get src */
        /* give a hint for the common case */
        if (0 == lines && !use_db_sub
            &&   ( (e->key_len == 1 && strnEQ(e->key, "-",  1))
                || (e->key_len == 2 && strnEQ(e->key, "-e", 2)) )
        ) {
            av_store(src_av, 1, newSVpv("# source not available, try using use_db_sub=1 option.\n",0));
            lines = 1;
        }
        for (line = 1; line <= lines; ++line) { /* lines start at 1 */
            SV **svp = av_fetch(src_av, line, 0);
            STRLEN len = 0;
            char *src = (svp) ? SvPV(*svp, len) : "";
            /* outputting the tag and fid for each (non empty) line
             * is a little inefficient, but not enough to worry about */
            output_tag_int(NYTP_TAG_SRC_LINE, e->id);
            output_int(line);
            output_str(src, (I32)len);    /* includes newline */
            if (trace_level >= 5)
                logwarn("fid %d src line %d: %s\n", e->id, line, src);
            ++t_lines;
        }
    }

    if (trace_level >= 1)
        logwarn("wrote %ld source lines for %d files (%d skipped without savesrc option, %d others had no source available)\n",
            t_lines, t_save_src, t_has_src-t_save_src, t_no_src);
}


/**
 * Read an integer by decompressing the next 1 to 4 bytes of binary into a 32-
 * bit integer. See output_int() for the compression details.
 */
static unsigned int
read_int()
{
    unsigned char d;
    unsigned int newint;

    NYTP_read(in, &d, sizeof(d), "integer prefix");

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
        NYTP_read(in, buffer, length, "integer");
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
read_nv()
{
    NV nv;
    /* no error checking on the assumption that a later token read will
     * detect the error/eof condition
     */
    NYTP_read(in, (unsigned char *)&nv, sizeof(NV), "float");
    return nv;
}


SV *
normalize_eval_seqn(pTHX_ SV *sv) {
    /* in-place-edit any eval sequence numbers to 0 */
    int found = 0;
    STRLEN len;
    char *start = SvPV(sv, len);
    char *src = start;
    char *dst = start;

    if (len < 5)
        return sv;

    /* effectively does $sv =~ s/(?<!$assert) \s \d+/eval 0/xg;
     * where $assert is qr/\((?:re_)?eval/ so it only matches '(eval ' and '(re_eval '
     */
    while (*src) {
        if (*src == ' ' && isdigit(*(src+1)) &&
            (  (src-start >= 5 && strnEQ(src-5,    "(eval ", 6))
            || (src-start >= 8 && strnEQ(src-8, "(re_eval ", 8)) )
        ) {
            ++found;
            if (trace_level >= 5)
                logwarn("found eval at '%s' in %s\n", src, start);
            *dst++ = ' ';
            *dst++ = '0';
             src++; /* skip space */
             src++; /* skip first digit */
            while (isdigit(*src)) { /* skip any extra digits */
                ++src;
            }
        }
        else {
            *dst++ = *src++;
        }
    }
    if (found) {
        *dst++ = '\0';
        SvCUR_set(sv, strlen(start));
        if (trace_level >= 5)
            logwarn("edited it to: %s\n", start);
    }

    return sv;
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
store_attrib_sv(pTHX_ HV *attr_hv, const char *text, SV *value_sv)
{
    (void)hv_store(attr_hv, text, (I32)strlen(text), value_sv, 0);
    if (trace_level >= 1)
        logwarn(": %s = '%s'\n", text, SvPV_nolen(value_sv));
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

    av_extend(fid_fileinfo_av, 64);               /* grow it up front. */
    av_extend(fid_srclines_av, 64);
    av_extend(fid_line_time_av, 64);

    if (FILE_STATE(in) != NYTP_FILE_STDIO) {
        compressed_io_croak(in, "load_profile_data_from_stream");
    }
    if (2 != fscanf(in->file, "NYTProf %d %d\n", &file_major, &file_minor)) {
        croak("Profile format error while parsing header");
    }
    if (file_major != 3)
        croak("Profile format version %d.%d not supported by %s %s",
            file_major, file_minor, __FILE__, XS_VERSION);

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
                unsigned int ticks    = read_int();
                unsigned int file_num = read_int();
                unsigned int line_num = read_int();

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
                        sv_setiv(cb_args[i], read_int()); XPUSHs(cb_args[i++]); /* block_line_num */
                        sv_setiv(cb_args[i], read_int()); XPUSHs(cb_args[i++]); /* sub_line_num */
                    }

                    PUTBACK;
                    call_sv(cb, G_DISCARD);
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
                if (trace_level >= 3) {
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
                unsigned int file_num      = read_int();
                unsigned int eval_file_num = read_int();
                unsigned int eval_line_num = read_int();
                unsigned int fid_flags     = read_int();
                unsigned int file_size     = read_int();
                unsigned int file_mtime    = read_int();

                filename_sv = read_str(aTHX_ NULL);
                if (eval_file_num)
                    normalize_eval_seqn(aTHX_ filename_sv);

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
                    break;
                }

                if (trace_level >= 2) {
                    logwarn("Fid %2u is %s (eval %u:%u) 0x%x sz%u mt%u\n",
                        file_num, SvPV_nolen(filename_sv), eval_file_num, eval_line_num,
                        fid_flags, file_size, file_mtime);
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
                unsigned int file_num = read_int();
                unsigned int line_num = read_int();
                SV *src = read_str(aTHX_ NULL);
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

            case NYTP_TAG_SUB_LINE_RANGE:
            {
                AV *av;
                SV *sv;
                unsigned int fid        = read_int();
                unsigned int first_line = read_int();
                unsigned int last_line  = read_int();
                int skip_subinfo_store = 0;
                SV *subname_sv = normalize_eval_seqn(aTHX_ read_str(aTHX_ tmp_str1_sv));
                STRLEN subname_len;
                char *subname_pv;

                if (cb) {
                    PUSHMARK(SP);

                    i = 0;
                    sv_setpvs(cb_args[i], "SUB_LINE_RANGE"); XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], fid);               XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], first_line);        XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], last_line);         XPUSHs(cb_args[i++]);
                    sv_setsv(cb_args[i], subname_sv);        XPUSHs(cb_args[i++]);

                    PUTBACK;
                    call_sv(cb, G_DISCARD);
                    break;
                }

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
                (void)hv_store((HV *)sv, subname_pv, (I32)subname_len, newRV((SV*)av), 0);

                break;
            }

            case NYTP_TAG_SUB_CALLERS:
            {
                char text[MAXPATHLEN*2];
                SV *sv;
                AV *subinfo_av;
                int len;
                unsigned int fid   = read_int();
                SV *caller_subname_sv = normalize_eval_seqn(aTHX_ read_str(aTHX_ tmp_str2_sv));
                unsigned int line  = read_int();
                unsigned int count = read_int();
                NV incl_time       = read_nv();
                NV excl_time       = read_nv();
                NV ucpu_time       = read_nv();
                NV scpu_time       = read_nv();
                NV reci_time       = read_nv();
                UV rec_depth       = read_int();
                SV *called_subname_sv = normalize_eval_seqn(aTHX_ read_str(aTHX_ tmp_str1_sv));

                if (cb) {
                    PUSHMARK(SP);

                    i = 0;
                    sv_setpvs(cb_args[i], "SUB_CALLERS"); XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], fid);            XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], line);           XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], count);          XPUSHs(cb_args[i++]);
                    sv_setnv(cb_args[i], incl_time);      XPUSHs(cb_args[i++]);
                    sv_setnv(cb_args[i], excl_time);      XPUSHs(cb_args[i++]);
                    sv_setnv(cb_args[i], ucpu_time);      XPUSHs(cb_args[i++]);
                    sv_setnv(cb_args[i], scpu_time);      XPUSHs(cb_args[i++]);
                    sv_setnv(cb_args[i], reci_time);      XPUSHs(cb_args[i++]);
                    sv_setiv(cb_args[i], rec_depth);      XPUSHs(cb_args[i++]);
                    sv_setsv(cb_args[i], called_subname_sv);     XPUSHs(cb_args[i++]);
                    assert(i <= C_ARRAY_LENGTH(cb_args));

                    PUTBACK;
                    call_sv(cb, G_DISCARD);
                    break;
                }

                if (trace_level >= 3)
                    logwarn("Sub %s called by %s %u:%u: count %d, incl %f, excl %f, ucpu %f scpu %f\n",
                        SvPV_nolen(called_subname_sv), SvPV_nolen(caller_subname_sv), fid, line,
                        count, incl_time, excl_time, ucpu_time, scpu_time);

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
                    else if (!instr(SvPV_nolen(called_subname_sv), "__ANON__[(eval") || trace_level)
                        logwarn("Merging extra sub caller info for %s %d:%d\n",
                            SvPV_nolen(called_subname_sv), fid, line);
                    av = (AV *)SvRV(sv);
                    sv = *av_fetch(av, NYTP_SCi_CALL_COUNT, 1);
                    sv_setuv(sv, (SvOK(sv)) ? SvUV(sv) + count : count);
                    sv = *av_fetch(av, NYTP_SCi_INCL_RTIME, 1);
                    sv_setnv(sv, (SvOK(sv)) ? SvNV(sv) + incl_time : incl_time);
                    sv = *av_fetch(av, NYTP_SCi_EXCL_RTIME, 1);
                    sv_setnv(sv, (SvOK(sv)) ? SvNV(sv) + excl_time : excl_time);
                    sv = *av_fetch(av, NYTP_SCi_INCL_UTIME, 1);
                    sv_setnv(sv, (SvOK(sv)) ? SvNV(sv) + ucpu_time : ucpu_time);
                    sv = *av_fetch(av, NYTP_SCi_INCL_STIME, 1);
                    sv_setnv(sv, (SvOK(sv)) ? SvNV(sv) + scpu_time : scpu_time);
                    sv = *av_fetch(av, NYTP_SCi_RECI_RTIME, 1);
                    sv_setnv(sv, (SvOK(sv)) ? SvNV(sv) + scpu_time : reci_time);
                    sv = *av_fetch(av, NYTP_SCi_REC_DEPTH,  1);
                    if (!SvOK(sv) || SvUV(sv) < rec_depth) /* max() */
                        sv_setuv(sv, rec_depth);

                    /* XXX temp hack way to store calling subname */
                    sv = *av_fetch(av, NYTP_SCi_CALLING_SUB, 1);
                    if (!SvROK(sv))               /* autoviv */
                        sv_setsv(sv, newRV_noinc((SV*)newHV()));
                    hv_fetch_ent((HV *)SvRV(sv), caller_subname_sv, 1, 0);

                    /* add sub call to NYTP_FIDi_SUBS_CALLED hash of fid making the call */
                    /* => { line => { subname => [ ... ] } } */
                    fi = SvRV(*av_fetch(fid_fileinfo_av, fid, 1));
                    fi = *av_fetch((AV *)fi, NYTP_FIDi_SUBS_CALLED, 1);
                    fi = *hv_fetch((HV*)SvRV(fi), text, len, 1);
                    if (!SvROK(fi))               /* autoviv */
                        sv_setsv(fi, newRV_noinc((SV*)newHV()));
                    fi = HeVAL(hv_fetch_ent((HV *)SvRV(fi), called_subname_sv, 1, 0));
                    sv_setsv(fi, newRV((SV *)av));
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
                unsigned int pid  = read_int();
                unsigned int ppid = read_int();
                int len = sprintf(text, "%d", pid);
                profiler_start_time = read_nv();

                if (cb) {
                    PUSHMARK(SP);

                    i = 0;
                    sv_setpvs(cb_args[i], "PID_START");   XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], pid);            XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], ppid);           XPUSHs(cb_args[i++]);
                    sv_setnv(cb_args[i], profiler_start_time); XPUSHs(cb_args[i++]);

                    PUTBACK;
                    call_sv(cb, G_DISCARD);
                    break;
                }

                (void)hv_store(live_pids_hv, text, len, newSVuv(ppid), 0);
                if (trace_level)
                    logwarn("Start of profile data for pid %s (ppid %d, %"IVdf" pids live) at %"NVff"\n",
                        text, ppid, HvKEYS(live_pids_hv), profiler_start_time);

                store_attrib_sv(aTHX_ attr_hv, "profiler_start_time", newSVnv(profiler_start_time));

                break;
            }

            case NYTP_TAG_PID_END:
            {
                char text[MAXPATHLEN*2];
                unsigned int pid = read_int();
                int len = sprintf(text, "%d", pid);
                profiler_end_time = read_nv();

                if (cb) {
                    PUSHMARK(SP);

                    i = 0;
                    sv_setpvs(cb_args[i], "PID_END");  XPUSHs(cb_args[i++]);
                    sv_setuv(cb_args[i], pid);         XPUSHs(cb_args[i++]);
                    sv_setnv(cb_args[i], profiler_end_time);  XPUSHs(cb_args[i++]);

                    PUTBACK;
                    call_sv(cb, G_DISCARD);
                    break;
                }

                if (!hv_delete(live_pids_hv, text, len, 0))
                    logwarn("Inconsistent pids in profile data (pid %d not introduced)\n",
                        pid);
                if (trace_level)
                    logwarn("End of profile data for pid %s (%"IVdf" remaining) at %"NVff"\n", text,
                        HvKEYS(live_pids_hv), profiler_end_time);

                store_attrib_sv(aTHX_ attr_hv, "profiler_end_time", newSVnv(profiler_end_time));
                profiler_duration = profiler_end_time - profiler_start_time;
                store_attrib_sv(aTHX_ attr_hv, "profiler_duration", newSVnv(profiler_duration));

                break;
            }

            case NYTP_TAG_ATTRIBUTE:
            {
                char text[MAXPATHLEN*2];
                char *value, *end;
                SV *value_sv;
                if (NULL == NYTP_gets(in, text, sizeof(text)))
                    /* probably EOF */
                    croak("Profile format error reading attribute");
                if ((NULL == (value = strchr(text, '=')))
                    ||  (NULL == (end   = strchr(text, '\n')))
                ) {
                    logwarn("attribute malformed '%s'\n", text);
                    continue;
                }
                *value++ = '\0';
                value_sv = newSVpvn(value, end-value);

                if (cb) {
                    PUSHMARK(SP);

                    i = 0;
                    sv_setpvs(cb_args[i], "ATTRIBUTE");  XPUSHs(cb_args[i++]);
                    sv_setpv(cb_args[i], text);          XPUSHs(cb_args[i++]);
                    sv_setsv(cb_args[i], value_sv);      XPUSHs(cb_args[i++]);

                    PUTBACK;
                    call_sv(cb, G_DISCARD);
                }

                store_attrib_sv(aTHX_ attr_hv, text, value_sv);
                if ('t' == *text && strEQ(text, "ticks_per_sec")) {
                    ticks_per_sec = (unsigned int)SvUV(value_sv);
                }
                else if ('n' == *text && strEQ(text, "nv_size")) {
                    if (sizeof(NV) != atoi(value))
                        croak("Profile data created by incompatible perl config (NV size %d but ours is %d)",
                            atoi(value), (int)sizeof(NV));
                }
                    
                break;
            }

            case NYTP_TAG_COMMENT:
            {
                char text[MAXPATHLEN*2];
                if (NULL == NYTP_gets(in, text, sizeof(text)))
                    /* probably EOF */
                    croak("Profile format error reading comment");

                if (cb) {
                    PUSHMARK(SP);

                    i = 0;
                    sv_setpvs(cb_args[i], "COMMENT"); XPUSHs(cb_args[i++]);
                    sv_setpv(cb_args[i], text);       XPUSHs(cb_args[i++]);

                    PUTBACK;
                    call_sv(cb, G_DISCARD);
                    break;
                }

                if (trace_level >= 1)
                    logwarn("# %s", text); /* includes \n */
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
    }
    sv_free((SV*)live_pids_hv);
    sv_free(tmp_str1_sv);
    sv_free(tmp_str2_sv);

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
    store_attrib_sv(aTHX_ attr_hv, "total_stmts_measured",   newSVnv(total_stmts_measured));
    store_attrib_sv(aTHX_ attr_hv, "total_stmts_discounted", newSVnv(total_stmts_discounted));
    store_attrib_sv(aTHX_ attr_hv, "total_stmts_duration",   newSVnv(total_stmts_duration));
    store_attrib_sv(aTHX_ attr_hv, "total_sub_calls",        newSVnv(total_sub_calls));

    if (1) {
        int show_summary_stats = (trace_level >= 1);

        if (profiler_end_time && total_stmts_duration > profiler_duration * 1.1) {
            logwarn("The sum of the statement timings is %.1f%% of the total time profiling."
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
    (void)hv_stores(profile_modes, "fid_line_time", newSVpvf("line"));
    if (fid_block_time_av) {
        (void)hv_stores(profile_hv, "fid_block_time",      newRV_noinc((SV*)fid_block_time_av));
        (void)hv_stores(profile_modes, "fid_block_time", newSVpvf("block"));
    }
    if (fid_sub_time_av) {
        (void)hv_stores(profile_hv, "fid_sub_time",    newRV_noinc((SV*)fid_sub_time_av));
        (void)hv_stores(profile_modes, "fid_sub_time", newSVpvf("sub"));
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
    newCONSTSUB(stash, "NYTP_SCi_INCL_UTIME",   newSViv(NYTP_SCi_INCL_UTIME));
    newCONSTSUB(stash, "NYTP_SCi_INCL_STIME",   newSViv(NYTP_SCi_INCL_STIME));
    newCONSTSUB(stash, "NYTP_SCi_RECI_RTIME",   newSViv(NYTP_SCi_RECI_RTIME));
    newCONSTSUB(stash, "NYTP_SCi_REC_DEPTH",    newSViv(NYTP_SCi_REC_DEPTH));
    newCONSTSUB(stash, "NYTP_SCi_CALLING_SUB",  newSViv(NYTP_SCi_CALLING_SUB));
    /* others */
    newCONSTSUB(stash, "NYTP_DEFAULT_COMPRESSION", newSViv(default_compression_level));
}


MODULE = Devel::NYTProf     PACKAGE = Devel::NYTProf::Test

PROTOTYPES: DISABLE

void
example_xsub(char *unused="", char *action="")
    CODE:
    if (!action || !*action)
        XSRETURN(0);
    if (strEQ(action,"die"))
        croak("example_xsub(die)");
    logwarn("example_xsub: unknown action '%s'\n", action);

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
    if (use_db_sub)
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
        if (trace_level >= 1)
            logwarn("enable_profile defered until END\n");
        av_unshift(PL_endav, 1);  /* we want to be first */
        av_store(PL_endav, 0, SvREFCNT_inc(enable_profile_sv));
    }
    /* we want to END { finish_profile() } but we want it to be the last END
     * block run so we don't push it into PL_endav until INIT phase.
     * so it's likely to be the last thing run.
     */
    av_push(PL_endav, (SV *)get_cv("DB::finish_profile", GV_ADDWARN));



MODULE = Devel::NYTProf     PACKAGE = Devel::NYTProf::Data

PROTOTYPES: DISABLE

HV*
load_profile_data_from_file(file,cb=NULL)
char *file;
SV* cb;
    CODE:
    if (trace_level)
        logwarn("reading profile data from file %s\n", file);
    in = NYTP_open(file, "rb");
    if (in == NULL) {
        croak("Failed to open input '%s': %s", file, strerror(errno));
    }
    RETVAL = load_profile_data_from_stream(cb);
    NYTP_close(in, 0);
    OUTPUT:
    RETVAL
