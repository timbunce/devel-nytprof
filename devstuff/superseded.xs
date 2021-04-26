/**
 * Return a unique persistent id number for a string.
 *
 * XXX Currently not used, so may trigger compiler warnings, but is intended to be
 * used to assign ids to strings like subroutine names like we do for file ids.
 */
static unsigned int
get_str_id(pTHX_ char* str, STRLEN len)
{
    str_hash_entry *found;
    hash_op(&strhash, str, len, (Hash_entry**)&found, 1);
    return found->he.id;
}


