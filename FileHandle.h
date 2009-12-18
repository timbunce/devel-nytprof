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
char *NYTP_gets(NYTP_file ifile, char *buffer, unsigned int len);
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

void NYTProf_croak_if_not_stdio(NYTP_file file, const char *function);
