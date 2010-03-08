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

/* Arguably this header is naughty, as it's not self contained, because it
   assumes that stdlib.h has already been included (via perl.h)  */

typedef struct NYTP_file_t *NYTP_file;

void NYTP_start_deflate(NYTP_file file, int compression_level);
void NYTP_start_inflate(NYTP_file file);

NYTP_file NYTP_open(const char *name, const char *mode);
char *NYTP_gets(NYTP_file ifile, char **buffer, size_t *len);
size_t NYTP_read_unchecked(NYTP_file ifile, void *buffer, size_t len);
size_t NYTP_read(NYTP_file ifile, void *buffer, size_t len, const char *what);
size_t NYTP_write(NYTP_file ofile, const void *buffer, size_t len);
int NYTP_scanf(NYTP_file ifile, const char *format, ...);
int NYTP_printf(NYTP_file ofile, const char *format, ...);
int NYTP_flush(NYTP_file file);
int NYTP_eof(NYTP_file ifile);
long NYTP_tell(NYTP_file file);
int NYTP_close(NYTP_file file, int discard);

const char *NYTP_fstrerror(NYTP_file file);
#ifdef HAS_ZLIB
const char *NYTP_type_of_offset(NYTP_file file);
#else
#  define NYTP_type_of_offset(file) ""
#endif

#define NYTP_TAG_ATTRIBUTE       ':'    /* :name=value\n */
#define NYTP_TAG_COMMENT         '#'    /* till newline */
#define NYTP_TAG_TIME_BLOCK      '*'
#define NYTP_TAG_TIME_LINE       '+'
#define NYTP_TAG_DISCOUNT        '-'
#define NYTP_TAG_NEW_FID         '@'
#define NYTP_TAG_SRC_LINE        'S'    /* fid, line, str */
#define NYTP_TAG_SUB_INFO        's'
#define NYTP_TAG_SUB_CALLERS     'c'
#define NYTP_TAG_PID_START       'P'
#define NYTP_TAG_PID_END         'p'
#define NYTP_TAG_STRING          '\'' 
#define NYTP_TAG_STRING_UTF8     '"' 
#define NYTP_TAG_START_DEFLATE   'z' 

void NYTProf_croak_if_not_stdio(NYTP_file file, const char *function);

size_t NYTP_write_comment(NYTP_file ofile, const char *format, ...);
size_t NYTP_write_attribute_string(NYTP_file ofile,
                                   const char *key, size_t key_len,
                                   const char *value, size_t value_len);
size_t NYTP_write_attribute_signed(NYTP_file ofile, const char *key,
                                   size_t key_len, long value);
size_t NYTP_write_attribute_unsigned(NYTP_file ofile, const char *key,
                                     size_t key_len, unsigned long value);
size_t NYTP_write_process_start(NYTP_file ofile, unsigned int pid,
                                unsigned int ppid, NV time_of_day);
size_t NYTP_write_process_end(NYTP_file ofile, unsigned int pid,
                              NV time_of_day);
size_t NYTP_write_new_fid(NYTP_file ofile, unsigned int id,
                          unsigned int eval_fid, unsigned int eval_line_num,
                          unsigned int flags, unsigned int size,
                          unsigned int mtime, const char *name, I32 len);
size_t NYTP_write_time_block(NYTP_file ofile, unsigned int elapsed,
                             unsigned int fid, unsigned int line,
                             unsigned int last_block_line,
                             unsigned int last_sub_line);
size_t NYTP_write_time_line(NYTP_file ofile, unsigned int elapsed,
                            unsigned int fid, unsigned int line);
size_t NYTP_write_sub_info(NYTP_file ofile, unsigned int fid,
                           const char *name, I32 len,
                           unsigned int first_line, unsigned int last_line);
