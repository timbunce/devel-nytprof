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

/* FIXME - The callers of these functions should be refactored into their own
   library file, with a public API, the XS interface adapted to use that API,
   and these 3 return to being static functions, within that library.  */

void output_tag_int(NYTP_file file, unsigned char tag, unsigned int);
void output_str(NYTP_file file, const char *str, I32 len);
void output_nv(NYTP_file file, NV nv);

#define NYTP_TAG_NO_TAG          '\0'   /* Used as a flag to mean "no tag" */
#define     output_int(fh, i)   output_tag_int((fh), NYTP_TAG_NO_TAG, (unsigned int)(i))
