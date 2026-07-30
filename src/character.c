/* Basic character support.

Copyright (C) 2001-2026 Free Software Foundation, Inc.
Copyright (C) 1995, 1997, 1998, 2001 Electrotechnical Laboratory, JAPAN.
  Licensed to the Free Software Foundation.
Copyright (C) 2003, 2004, 2005, 2006, 2007, 2008, 2009, 2010, 2011
  National Institute of Advanced Industrial Science and Technology (AIST)
  Registration Number H13PRO009

This file is part of GNU Emacs.

GNU Emacs is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

GNU Emacs is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.  */

/* At first, see the document in `character.h' to understand the code
   in this file.  */

#include <config.h>

#include <stdio.h>

#include <sys/types.h>
#include <intprops.h>
#include "lisp.h"
#include "character.h"
#include "buffer.h"
#include "frame.h"
#include "dispextern.h"
#include "composite.h"
#include "disptab.h"

/* Char-table of information about which character to unify to which
   Unicode character.  Mainly used by the macro MAYBE_UNIFY_CHAR.  */
Lisp_Object Vchar_unify_table;



/* If character code C has modifier masks, reflect them to the
   character code if possible.  Return the resulting code.  */

EMACS_INT
char_resolve_modifier_mask (EMACS_INT c)
{
  /* A non-ASCII character can't reflect modifier bits to the code.  */
  if (! ASCII_CHAR_P ((c & ~CHAR_MODIFIER_MASK)))
    return c;

  /* For Meta, Shift, and Control modifiers, we need special care.  */
  if (c & CHAR_SHIFT)
    {
      /* Shift modifier is valid only with [A-Za-z].  */
      if ((c & 0377) >= 'A' && (c & 0377) <= 'Z')
	c &= ~CHAR_SHIFT;
      else if ((c & 0377) >= 'a' && (c & 0377) <= 'z')
	c = (c & ~CHAR_SHIFT) - ('a' - 'A');
      /* Shift modifier for control characters and SPC is ignored.  */
      else if ((c & ~CHAR_MODIFIER_MASK) <= 0x20)
	c &= ~CHAR_SHIFT;
    }
  if (c & CHAR_CTL)
    {
      /* Simulate the code in lread.c.  */
      /* Allow `\C- ' and `\C-?'.  */
      if ((c & 0377) == ' ')
	c &= ~0177 & ~ CHAR_CTL;
      else if ((c & 0377) == '?')
	c = 0177 | (c & ~0177 & ~CHAR_CTL);
      /* ASCII control chars are made from letters (both cases),
	 as well as the non-letters within 0100...0137.  */
      else if ((c & 0137) >= 0101 && (c & 0137) <= 0132)
	c &= (037 | (~0177 & ~CHAR_CTL));
      else if ((c & 0177) >= 0100 && (c & 0177) <= 0137)
	c &= (037 | (~0177 & ~CHAR_CTL));
    }
#if 0	/* This is outside the scope of this function.  (bug#4751)  */
  if (c & CHAR_META)
    {
      /* Move the meta bit to the right place for a string.  */
      c = (c & ~CHAR_META) | 0x80;
    }
#endif

  return c;
}


/* Store multibyte form of character C at P.  If C has modifier bits,
   handle them appropriately.  */

int
char_string (unsigned int c, unsigned char *p)
{
  int bytes;

  if (c & CHAR_MODIFIER_MASK)
    {
      c = char_resolve_modifier_mask (c);
      /* If C still has any modifier bits, just ignore it.  */
      c &= ~CHAR_MODIFIER_MASK;
    }

  if (c <= MAX_3_BYTE_CHAR)
    {
      bytes = CHAR_STRING (c, p);
    }
  else if (c <= MAX_4_BYTE_CHAR)
    {
      p[0] = (0xF0 | (c >> 18));
      p[1] = (0x80 | ((c >> 12) & 0x3F));
      p[2] = (0x80 | ((c >> 6) & 0x3F));
      p[3] = (0x80 | (c & 0x3F));
      bytes = 4;
    }
  else if (c <= MAX_5_BYTE_CHAR)
    {
      p[0] = 0xF8;
      p[1] = (0x80 | ((c >> 18) & 0x0F));
      p[2] = (0x80 | ((c >> 12) & 0x3F));
      p[3] = (0x80 | ((c >> 6) & 0x3F));
      p[4] = (0x80 | (c & 0x3F));
      bytes = 5;
    }
  else if (c <= MAX_CHAR)
    {
      c = CHAR_TO_BYTE8 (c);
      bytes = BYTE8_STRING (c, p);
    }
  else
    error ("Invalid character: %x", c);

  return bytes;
}


/* Translate character C by translation table TABLE.  If no translation is
   found in TABLE, return the untranslated character.  If TABLE is a list,
   elements are char tables.  In that case, recursively translate C by all the
   tables in the list.  */

int
translate_char (Lisp_Object table, int c)
{
  if (CHAR_TABLE_P (table))
    {
      Lisp_Object ch;

      ch = CHAR_TABLE_REF (table, c);
      if (CHARACTERP (ch))
	c = XFIXNUM (ch);
    }
  else
    {
      for (; CONSP (table); table = XCDR (table))
	c = translate_char (XCAR (table), c);
    }
  return c;
}

DEFUN ("characterp", Fcharacterp, Scharacterp, 1, 2, 0,
       doc: /* Return non-nil if OBJECT is a character.
In Emacs Lisp, characters are represented by character codes, which
are non-negative integers.  The function `max-char' returns the
maximum character code.
usage: (characterp OBJECT)  */
       attributes: const)
  (Lisp_Object object, Lisp_Object ignore)
{
  return (CHARACTERP (object) ? Qt : Qnil);
}

DEFUN ("max-char", Fmax_char, Smax_char, 0, 1, 0,
       doc: /* Return the maximum character code.
If UNICODE is non-nil, return the maximum character code defined
by the Unicode Standard.  */
       attributes: const)
  (Lisp_Object unicode)
{
  return (!NILP (unicode)
	  ? make_fixnum (MAX_UNICODE_CHAR)
	  : make_fixnum (MAX_CHAR));
}

DEFUN ("unibyte-char-to-multibyte", Funibyte_char_to_multibyte,
       Sunibyte_char_to_multibyte, 1, 1, 0,
       doc: /* Convert the byte CH to multibyte character.  */)
  (Lisp_Object ch)
{
  int c;

  CHECK_CHARACTER (ch);
  c = XFIXNAT (ch);
  if (c >= 0x100)
    error ("Not a unibyte character: %d", c);
  return make_fixnum (make_char_multibyte (c));
}

DEFUN ("multibyte-char-to-unibyte", Fmultibyte_char_to_unibyte,
       Smultibyte_char_to_unibyte, 1, 1, 0,
       doc: /* Convert the multibyte character CH to a byte.
If the multibyte character does not represent a byte, return -1.  */)
  (Lisp_Object ch)
{
  int cm;

  CHECK_CHARACTER (ch);
  cm = XFIXNAT (ch);
  if (cm < 256)
    /* Can't distinguish a byte read from a unibyte buffer from
       a latin1 char, so let's let it slide.  */
    return ch;
  else
    {
      int cu = CHAR_TO_BYTE_SAFE (cm);
      return make_fixnum (cu);
    }
}


/* Emoji sequence width calculation for terminal display.
   Like the kitty keyboard protocol parser, this handles multi-codepoint
   sequences directly in C rather than relying on font shaping.

   Terminals display emoji sequences (ZWJ, skin tone, flags, keycap,
   tag sequences) as a single 2-column-wide glyph.  Without
   sequence-aware parsing, Emacs sums individual codepoint widths
   and gets the wrong answer (e.g. 8 instead of 2 for a family emoji).  */

/* Return true if C is an Emoji_Presentation=Yes codepoint, i.e. one
   that terminals render as a 2-column emoji glyph by default.  This
   covers the same ranges set to width 2 in characters.el.  */

static bool
emoji_presentation_p (int c)
{
  /* Fast reject for common ASCII / Latin range.  */
  if (c < 0x231A)
    return false;

  /* Miscellaneous Symbols and Dingbats range.  */
  if (c <= 0x2BFF)
    {
      switch (c)
        {
        case 0x231A: case 0x231B:
        case 0x23E9: case 0x23EA: case 0x23EB: case 0x23EC:
        case 0x23F0: case 0x23F3:
        case 0x25FD: case 0x25FE:
        case 0x2614: case 0x2615:
        case 0x267F:
        case 0x2693:
        case 0x26A1:
        case 0x26AA: case 0x26AB:
        case 0x26BD: case 0x26BE:
        case 0x26C4: case 0x26C5:
        case 0x26CE:
        case 0x26D4:
        case 0x26EA:
        case 0x26F2: case 0x26F3:
        case 0x26F5:
        case 0x26FA:
        case 0x26FD:
        case 0x2705:
        case 0x270A: case 0x270B:
        case 0x2728:
        case 0x274C: case 0x274E:
        case 0x2753: case 0x2754: case 0x2755:
        case 0x2757:
        case 0x2795: case 0x2796: case 0x2797:
        case 0x27B0: case 0x27BF:
        case 0x2B1B: case 0x2B1C:
        case 0x2B50: case 0x2B55:
          return true;
        }
      if (c >= 0x2648 && c <= 0x2653)
        return true;
      return false;
    }

  /* Supplementary Multilingual Plane emoji.  */
  if (c >= 0x1F000)
    {
      /* Regional Indicator Symbols.  */
      if (c >= 0x1F1E6 && c <= 0x1F1FF)
        return true;

      /* Main emoji blocks.  Rather than listing every sub-range,
         use the contiguous blocks from Unicode Emoji data.  */
      if (c >= 0x1F300 && c <= 0x1F64F)
        return true;
      if (c >= 0x1F680 && c <= 0x1F6FC)
        return true;
      if (c >= 0x1F7E0 && c <= 0x1F7EB)
        return true;
      if (c == 0x1F7F0)
        return true;
      if (c >= 0x1F90C && c <= 0x1F9FF)
        return true;
      if (c >= 0x1FA70 && c <= 0x1FAF8)
        return true;

      /* Additional specific emoji.  */
      if (c == 0x1F004 || c == 0x1F0CF || c == 0x1F18E)
        return true;
      if (c >= 0x1F191 && c <= 0x1F19A)
        return true;
      if (c == 0x1F201 || c == 0x1F21A || c == 0x1F22F)
        return true;
      if (c >= 0x1F232 && c <= 0x1F236)
        return true;
      if (c >= 0x1F238 && c <= 0x1F23A)
        return true;
      if (c >= 0x1F250 && c <= 0x1F251)
        return true;
      if (c >= 0x1F3FB && c <= 0x1F3FF)
        return true;
    }

  return false;
}

/* Return true if C is an Emoji=Yes but Emoji_Presentation=No codepoint,
   i.e. a "text-default" emoji that becomes a 2-column emoji glyph only
   when followed by VS16 (U+FE0F).  Examples: © ® ⚠ ☁ ✈ ⚔ ♻ ☀ ⬆.
   Derived from emoji-sequences.txt (Unicode 17.0):
     Basic_Emoji entries that contain FE0F.
   This matches kitty's text sizing protocol algorithm:
     "All Basic_Emoji have width two unless they are followed
     by FE0F in the file."  */

static bool
emoji_text_default_p (int c)
{
  /* U+00A9 COPYRIGHT SIGN and U+00AE REGISTERED SIGN.
     These are Basic_Emoji that require FE0F per emoji-sequences.txt.  */
  if (c == 0x00A9 || c == 0x00AE)
    return true;

  /* BMP text-default emoji (108 codepoints from 0x203C up).  */
  if (c < 0x203C)
    return false;

  if (c <= 0x3299)
    {
      switch (c)
        {
        case 0x203C: case 0x2049: case 0x2122: case 0x2139:
          return true;
        }

      if (c >= 0x2194 && c <= 0x2199) return true;
      if (c >= 0x21A9 && c <= 0x21AA) return true;

      if (c == 0x2328 || c == 0x23CF) return true;
      if (c >= 0x23ED && c <= 0x23EF) return true;
      if (c >= 0x23F1 && c <= 0x23F2) return true;
      if (c >= 0x23F8 && c <= 0x23FA) return true;

      if (c == 0x24C2) return true;
      if (c >= 0x25AA && c <= 0x25AB) return true;
      if (c == 0x25B6 || c == 0x25C0) return true;
      if (c >= 0x25FB && c <= 0x25FC) return true;

      if (c >= 0x2600 && c <= 0x2604) return true;
      if (c == 0x260E || c == 0x2611) return true;
      if (c == 0x2618 || c == 0x261D) return true;
      if (c == 0x2620) return true;
      if (c >= 0x2622 && c <= 0x2623) return true;
      if (c == 0x2626 || c == 0x262A) return true;
      if (c >= 0x262E && c <= 0x262F) return true;
      if (c >= 0x2638 && c <= 0x263A) return true;
      if (c == 0x2640 || c == 0x2642) return true;
      if (c >= 0x265F && c <= 0x2660) return true;
      if (c == 0x2663) return true;
      if (c >= 0x2665 && c <= 0x2666) return true;
      if (c == 0x2668 || c == 0x267B || c == 0x267E) return true;
      if (c == 0x2692) return true;
      if (c >= 0x2694 && c <= 0x2697) return true;
      if (c == 0x2699) return true;
      if (c >= 0x269B && c <= 0x269C) return true;
      if (c == 0x26A0 || c == 0x26A7) return true;
      if (c >= 0x26B0 && c <= 0x26B1) return true;
      if (c == 0x26C8 || c == 0x26CF || c == 0x26D1 || c == 0x26D3) return true;
      if (c == 0x26E9) return true;
      if (c >= 0x26F0 && c <= 0x26F1) return true;
      if (c == 0x26F4) return true;
      if (c >= 0x26F7 && c <= 0x26F9) return true;

      if (c == 0x2702) return true;
      if (c >= 0x2708 && c <= 0x2709) return true;
      if (c >= 0x270C && c <= 0x270D) return true;
      if (c == 0x270F || c == 0x2712 || c == 0x2714 || c == 0x2716) return true;
      if (c == 0x271D || c == 0x2721) return true;
      if (c >= 0x2733 && c <= 0x2734) return true;
      if (c == 0x2744 || c == 0x2747) return true;
      if (c >= 0x2763 && c <= 0x2764) return true;
      if (c == 0x27A1) return true;
      if (c >= 0x2934 && c <= 0x2935) return true;
      if (c >= 0x2B05 && c <= 0x2B07) return true;

      if (c == 0x3030 || c == 0x303D || c == 0x3297 || c == 0x3299) return true;

      return false;
    }

  /* SMP text-default emoji (97 codepoints).  */
  if (c >= 0x1F170)
    {
      if (c >= 0x1F170 && c <= 0x1F171) return true;
      if (c >= 0x1F17E && c <= 0x1F17F) return true;
      if (c == 0x1F202 || c == 0x1F237) return true;
      if (c == 0x1F321) return true;
      if (c >= 0x1F324 && c <= 0x1F32C) return true;
      if (c == 0x1F336 || c == 0x1F37D) return true;
      if (c >= 0x1F396 && c <= 0x1F397) return true;
      if (c >= 0x1F399 && c <= 0x1F39B) return true;
      if (c >= 0x1F39E && c <= 0x1F39F) return true;
      if (c >= 0x1F3CB && c <= 0x1F3CE) return true;
      if (c >= 0x1F3D4 && c <= 0x1F3DF) return true;
      if (c == 0x1F3F3 || c == 0x1F3F5 || c == 0x1F3F7) return true;
      if (c == 0x1F43F || c == 0x1F441) return true;
      if (c == 0x1F4FD) return true;
      if (c >= 0x1F549 && c <= 0x1F54A) return true;
      if (c >= 0x1F56F && c <= 0x1F570) return true;
      if (c >= 0x1F573 && c <= 0x1F579) return true;
      if (c == 0x1F587) return true;
      if (c >= 0x1F58A && c <= 0x1F58D) return true;
      if (c == 0x1F590) return true;
      if (c == 0x1F5A5 || c == 0x1F5A8) return true;
      if (c >= 0x1F5B1 && c <= 0x1F5B2) return true;
      if (c == 0x1F5BC) return true;
      if (c >= 0x1F5C2 && c <= 0x1F5C4) return true;
      if (c >= 0x1F5D1 && c <= 0x1F5D3) return true;
      if (c >= 0x1F5DC && c <= 0x1F5DE) return true;
      if (c == 0x1F5E1 || c == 0x1F5E3 || c == 0x1F5E8) return true;
      if (c == 0x1F5EF || c == 0x1F5F3 || c == 0x1F5FA) return true;
      if (c == 0x1F6CB) return true;
      if (c >= 0x1F6CD && c <= 0x1F6CF) return true;
      if (c >= 0x1F6E0 && c <= 0x1F6E5) return true;
      if (c == 0x1F6E9 || c == 0x1F6F0 || c == 0x1F6F3) return true;
    }

  return false;
}

/* Return true if C is a Regional Indicator Symbol (U+1F1E6..U+1F1FF).  */
static bool
regional_indicator_p (int c)
{
  return c >= 0x1F1E6 && c <= 0x1F1FF;
}

/* Return true if C is an emoji skin-tone modifier (U+1F3FB..U+1F3FF).  */
static bool
emoji_modifier_p (int c)
{
  return c >= 0x1F3FB && c <= 0x1F3FF;
}

/* Return true if C is a tag character (U+E0020..U+E007E) or
   cancel tag (U+E007F), used in flag tag sequences like
   subdivision flags (e.g. 🏴󠁧󠁢󠁥󠁮󠁧󠁿 England flag).  */
static bool
emoji_tag_p (int c)
{
  return c >= 0xE0020 && c <= 0xE007F;
}



/* Scan an emoji sequence starting at STR (pointing into a UTF-8
   buffer of LIMIT total bytes).  If the codepoint at STR begins
   an emoji sequence, consume the full sequence and return:
     - The display width (always 2 for a valid emoji sequence)
     - *CONSUMED set to the number of bytes consumed
   If STR does not start an emoji sequence, return 0 and leave
   *CONSUMED unchanged.

   Recognized emoji sequence types (per UTS #51):
   1. Emoji + ZWJ + Emoji + ... (ZWJ sequences: family, profession)
   2. Emoji + Skin-tone modifier (modified emoji)
   3. Regional_Indicator + Regional_Indicator (flag pairs)
   4. Emoji + VS16 (text-to-emoji presentation switch)
   5. Emoji + Tag_chars + Cancel_Tag (subdivision flag sequences)
   6. [0-9#*] + VS16 + U+20E3 (keycap sequences)

   Each of these displays as a single 2-column glyph in a terminal.  */

static int
emoji_sequence_width (const unsigned char *str, ptrdiff_t limit,
                      ptrdiff_t *consumed)
{
  if (limit <= 0)
    return 0;

  int bytes;
  int c = string_char_and_length (str, &bytes);

  /* Case 1: Keycap sequences: [0-9#*] + FE0F + 20E3.
     These are single-width ASCII chars that become 2-wide emoji
     when followed by VS16 + combining enclosing keycap.  */
  if ((c >= '0' && c <= '9') || c == '#' || c == '*')
    {
      if (bytes < limit)
        {
          int b2;
          int c2 = string_char_and_length (str + bytes, &b2);
          if (c2 == 0xFE0F && bytes + b2 < limit)
            {
              int b3;
              int c3 = string_char_and_length (str + bytes + b2, &b3);
              if (c3 == 0x20E3)
                {
                  *consumed = bytes + b2 + b3;
                  return 2;
                }
            }
        }
      return 0;  /* Not a keycap sequence, return to normal processing.  */
    }

  /* Quick reject for non-emoji codepoints.  */
  if (c < 0x200D && !emoji_presentation_p (c) && !emoji_text_default_p (c))
    return 0;

  /* Case 2: Regional Indicator pairs -> flag emoji.  */
  if (regional_indicator_p (c))
    {
      if (bytes < limit)
        {
          int b2;
          int c2 = string_char_and_length (str + bytes, &b2);
          if (regional_indicator_p (c2))
            {
              *consumed = bytes + b2;
              return 2;
            }
        }
      /* Lone regional indicator -- use char-width-table default.  */
      return 0;
    }

  /* Case 3: Text-default emoji + VS16 (FE0F) -> emoji presentation.
     These are Emoji=Yes but Emoji_Presentation=No codepoints that
     become 2-column emoji only when followed by U+FE0F.
     Examples: U+26A0 WARNING SIGN, U+2708 AIRPLANE, etc.  */
  if (emoji_text_default_p (c))
    {
      if (bytes < limit)
        {
          int b2;
          int c2 = string_char_and_length (str + bytes, &b2);
          if (c2 == 0xFE0F)
            {
              /* Text-default emoji + VS16 = 2-column emoji.
                 Continue scanning for ZWJ continuations.  */
              ptrdiff_t pos = bytes + b2;

              for (;;)
                {
                  if (pos >= limit)
                    break;

                  int nb;
                  int next = string_char_and_length (str + pos, &nb);

                  /* Skin-tone modifier.  */
                  if (emoji_modifier_p (next))
                    {
                      pos += nb;
                      continue;
                    }

                  /* ZWJ followed by another emoji.  */
                  if (next == 0x200D && pos + nb < limit)
                    {
                      int nb2;
                      int after_zwj
                        = string_char_and_length (str + pos + nb, &nb2);
                      if (emoji_presentation_p (after_zwj)
                          || emoji_text_default_p (after_zwj)
                          || after_zwj == 0xFE0F)
                        {
                          pos += nb + nb2;
                          continue;
                        }
                      break;
                    }

                  /* VS16 after ZWJ target.  */
                  if (next == 0xFE0F)
                    {
                      pos += nb;
                      continue;
                    }

                  /* Combining Enclosing Keycap.  */
                  if (next == 0x20E3)
                    {
                      pos += nb;
                      continue;
                    }

                  break;
                }

              *consumed = pos;
              return 2;
            }
        }
      /* Text-default emoji without VS16 -- not an emoji sequence,
         fall through to normal width calculation.  */
      return 0;
    }

  /* For the remaining cases, the first codepoint must be
     an Emoji_Presentation=Yes character.  */
  if (!emoji_presentation_p (c))
    return 0;

  /* Now scan forward consuming emoji modifiers, ZWJ continuations,
     VS16, and tag sequences.  The whole thing = 2 columns.  */
  ptrdiff_t pos = bytes;

  for (;;)
    {
      if (pos >= limit)
        break;

      int nb;
      int next = string_char_and_length (str + pos, &nb);

      /* VS16 (Emoji presentation selector) -- consume it.  */
      if (next == 0xFE0F)
        {
          pos += nb;
          continue;
        }

      /* VS15 (Text presentation selector) -- switches to text
         presentation.  Per kitty text sizing protocol: when an
         Emoji_Presentation=Yes codepoint is followed by VS15,
         its width decreases to 1.  This only applies immediately
         after the base codepoint, not deep inside a ZWJ chain.  */
      if (next == 0xFE0E)
        {
          if (pos == bytes)
            {
              /* Immediately after base emoji -> width 1.  */
              *consumed = pos + nb;
              return 1;
            }
          /* Inside a multi-codepoint sequence, just consume it.  */
          pos += nb;
          continue;
        }

      /* Skin-tone modifier — consume it.  */
      if (emoji_modifier_p (next))
        {
          pos += nb;
          continue;
        }

      /* ZWJ (U+200D) followed by another emoji -- consume both.  */
      if (next == 0x200D && pos + nb < limit)
        {
          int nb2;
          int after_zwj = string_char_and_length (str + pos + nb, &nb2);
          if (emoji_presentation_p (after_zwj)
              || emoji_text_default_p (after_zwj)
              || after_zwj == 0xFE0F   /* VS16 (skip) */
              )
            {
              pos += nb + nb2;
              continue;
            }
          /* Unknown codepoint after ZWJ -- stop consuming.
             (Some terminals still render unknown ZWJ combos as
             fallback, but we can't predict their width.)  */
          break;
        }

      /* Tag characters (subdivision flag sequences like 🏴󠁧󠁢󠁥󠁮󠁧󠁿).  */
      if (emoji_tag_p (next))
        {
          /* Consume all tag characters until cancel tag U+E007F.  */
          while (pos < limit)
            {
              int tnb;
              int tc = string_char_and_length (str + pos, &tnb);
              pos += tnb;
              if (tc == 0xE007F)  /* Cancel tag = end of sequence.  */
                break;
              if (!emoji_tag_p (tc))
                break;
            }
          break;
        }

      /* Combining Enclosing Keycap (U+20E3) — consume it.  */
      if (next == 0x20E3)
        {
          pos += nb;
          continue;
        }

      /* Not a recognized continuation — sequence ends here.  */
      break;
    }

  /* If we consumed more than just the base character, this is a
     multi-codepoint emoji sequence → 2 columns.
     If it's just the base character, also return 2 since
     emoji_presentation_p characters are width 2.  */
  *consumed = pos;
  return 2;
}


/* Return width (columns) of C considering the buffer display table DP. */

static ptrdiff_t
char_width (int c, struct Lisp_Char_Table *dp)
{
  ptrdiff_t width = CHARACTER_WIDTH (c);

  if (dp)
    {
      Lisp_Object disp = DISP_CHAR_VECTOR (dp, c), ch;
      int i;

      if (VECTORP (disp))
	for (i = 0, width = 0; i < ASIZE (disp); i++)
	  {
	    int c = -1;
	    ch = AREF (disp, i);
	    if (GLYPH_CODE_P (ch))
	      c = GLYPH_CODE_CHAR (ch);
	    else if (CHARACTERP (ch))
	      c = XFIXNUM (ch);
	    if (c >= 0)
	      {
		int w = CHARACTER_WIDTH (c);
		if (ckd_add (&width, width, w))
		  string_overflow ();
	      }
	  }
    }
  return width;
}


DEFUN ("char-width", Fchar_width, Schar_width, 1, 1, 0,
       doc: /* Return width of CHAR in columns when displayed in the current buffer.
The width of CHAR is measured by how many columns it will occupy on the screen.
This is based on data in `char-width-table', and ignores the actual
metrics of the character's glyph as determined by its font.
If the display table in effect replaces CHAR on display with
something else, the function returns the width of the replacement.
Tab is taken to occupy `tab-width' columns.
usage: (char-width CHAR)  */)
  (Lisp_Object ch)
{
  int c;
  ptrdiff_t width;

  CHECK_CHARACTER (ch);
  c = XFIXNUM (ch);
  width = char_width (c, buffer_display_table ());
  return make_fixnum (width);
}

/* Return width of string STR of length LEN when displayed in the
   current buffer.  The width is measured by how many columns it
   occupies on the screen.  If PRECISION > 0, return the width of
   longest substring that doesn't exceed PRECISION, and set number of
   characters and bytes of the substring in *NCHARS and *NBYTES
   respectively.  */

ptrdiff_t
c_string_width (const unsigned char *str, ptrdiff_t len, int precision,
		ptrdiff_t *nchars, ptrdiff_t *nbytes)
{
  ptrdiff_t i = 0, i_byte = 0;
  ptrdiff_t width = 0;
  struct Lisp_Char_Table *dp = buffer_display_table ();

  while (i_byte < len)
    {
      ptrdiff_t seq_consumed = 0;
      int seq_width = emoji_sequence_width (str + i_byte, len - i_byte,
					    &seq_consumed);
      int bytes;
      ptrdiff_t thiswidth;

      if (seq_width > 0)
	{
	  thiswidth = seq_width;
	  bytes = seq_consumed;
	  /* Count characters in the consumed bytes.  */
	  const unsigned char *p = str + i_byte;
	  const unsigned char *pend = p + bytes;
	  int nchars_consumed = 0;
	  while (p < pend)
	    {
	      int cb;
	      string_char_and_length (p, &cb);
	      p += cb;
	      nchars_consumed++;
	    }
	  if (0 < precision && precision - width < thiswidth)
	    {
	      *nchars = i;
	      *nbytes = i_byte;
	      return width;
	    }
	  if (ckd_add (&width, width, thiswidth))
	    string_overflow ();
	  i += nchars_consumed;
	  i_byte += bytes;
	  continue;
	}

      int c = string_char_and_length (str + i_byte, &bytes);
      thiswidth = char_width (c, dp);

      if (0 < precision && precision - width < thiswidth)
	{
	  *nchars = i;
	  *nbytes = i_byte;
	  return width;
	}
      if (ckd_add (&width, width, thiswidth))
	string_overflow ();
      i++;
      i_byte += bytes;
    }

  if (precision > 0)
    {
      *nchars = i;
      *nbytes = i_byte;
    }

  return width;
}

/* Return width of string STR of length LEN when displayed in the
   current buffer.  The width is measured by how many columns it
   occupies on the screen.  */

ptrdiff_t
strwidth (const char *str, ptrdiff_t len)
{
  return c_string_width ((const unsigned char *) str, len, -1, NULL, NULL);
}

/* Return width of a (substring of a) Lisp string STRING when
   displayed in the current buffer.  The width is measured by how many
   columns it occupies on the screen while paying attention to
   compositions.  If PRECISION > 0, return the width of longest
   substring that doesn't exceed PRECISION, and set number of
   characters and bytes of the substring in *NCHARS and *NBYTES
   respectively.  FROM and TO are zero-based character indices that
   define the substring of STRING to consider.  If AUTO_COMP is
   non-zero, account for automatic compositions in STRING.  */

ptrdiff_t
lisp_string_width (Lisp_Object string, ptrdiff_t from, ptrdiff_t to,
		   ptrdiff_t precision, ptrdiff_t *nchars, ptrdiff_t *nbytes,
		   bool auto_comp)
{
  /* This set multibyte to 0 even if STRING is multibyte when it
     contains only ascii and eight-bit-graphic, but that's
     intentional.  */
  bool multibyte = SCHARS (string) < SBYTES (string);
  ptrdiff_t i = from, i_byte = from ? string_char_to_byte (string, from) : 0;
  ptrdiff_t from_byte = i_byte;
  ptrdiff_t width = 0;
  struct Lisp_Char_Table *dp = buffer_display_table ();
#ifdef HAVE_WINDOW_SYSTEM
  struct frame *f =
    (FRAMEP (selected_frame) && FRAME_LIVE_P (XFRAME (selected_frame)))
    ? XFRAME (selected_frame)
    : NULL;
  int font_width = -1;
  Lisp_Object default_font, frame_font;
#endif

  eassert (precision <= 0 || (nchars && nbytes));

  while (i < to)
    {
      ptrdiff_t chars, bytes, thiswidth;
      Lisp_Object val;
      ptrdiff_t cmp_id;
      ptrdiff_t ignore, end;

      if (find_composition (i, -1, &ignore, &end, &val, string)
	  && ((cmp_id = get_composition_id (i, i_byte, end - i, val, string))
	      >= 0))
	{
	  thiswidth = composition_table[cmp_id]->width;
	  chars = end - i;
	  bytes = string_char_to_byte (string, end) - i_byte;
	}
#ifdef HAVE_WINDOW_SYSTEM
      else if (auto_comp
	       && f && FRAME_WINDOW_P (f)
	       && multibyte
	       && find_automatic_composition (i, -1, i, &ignore,
					      &end, &val, string)
	       && end > i)
	{
	  int j;
	  for (j = 0; j < LGSTRING_GLYPH_LEN (val); j++)
	    if (NILP (LGSTRING_GLYPH (val, j)))
	      break;

	  int pixelwidth = composition_gstring_width (val, 0, j, NULL);

	  /* The below is somewhat expensive, so compute it only once
	     for the entire loop, and only if needed.  */
	  if (font_width < 0)
	    {
	      font_width = FRAME_COLUMN_WIDTH (f);
	      default_font = Fface_font (Qdefault, Qnil, Qnil);
	      frame_font = Fframe_parameter (Qnil, Qfont);

	      if (STRINGP (default_font) && STRINGP (frame_font)
		  && (SCHARS (default_font) != SCHARS (frame_font)
		      || SBYTES (default_font) != SBYTES (frame_font)
		      || memcmp (SDATA (default_font), SDATA (frame_font),
				 SBYTES (default_font))))
		{
		  Lisp_Object font_info = Ffont_info (default_font, Qnil);
		  if (VECTORP (font_info))
		    {
		      font_width = XFIXNUM (AREF (font_info, 11));
		      if (font_width <= 0)
			font_width = XFIXNUM (AREF (font_info, 10));
		    }
		}
	    }
	  thiswidth = (double) pixelwidth / font_width + 0.5;
	  chars = end - i;
	  bytes = string_char_to_byte (string, end) - i_byte;
	}
#endif	/* HAVE_WINDOW_SYSTEM */
      else if (multibyte)
	{
	  /* Check for emoji sequences that should be treated as a
	     single 2-column glyph.  Like the kitty keyboard protocol
	     parser, this handles sequences directly in C.  */
	  unsigned char *str = SDATA (string);
	  ptrdiff_t remaining = string_char_to_byte (string, to) - i_byte;
	  ptrdiff_t seq_consumed = 0;
	  int seq_width = emoji_sequence_width (str + i_byte, remaining,
						&seq_consumed);
	  if (seq_width > 0)
	    {
	      thiswidth = seq_width;
	      bytes = seq_consumed;
	      /* Count characters consumed.  */
	      const unsigned char *p = str + i_byte;
	      const unsigned char *pend = p + seq_consumed;
	      chars = 0;
	      while (p < pend)
		{
		  int cb;
		  string_char_and_length (p, &cb);
		  p += cb;
		  chars++;
		}
	    }
	  else
	    {
	      int cbytes;
	      int c = string_char_and_length (str + i_byte, &cbytes);
	      bytes = cbytes;
	      chars = 1;
	      thiswidth = char_width (c, dp);
	    }
	}
      else
	{
	  unsigned char *str = SDATA (string);
	  bytes = 1;
	  chars = 1;
	  thiswidth = char_width (str[i_byte], dp);
	}

      if (0 < precision && precision - width < thiswidth)
	{
	  *nchars = i - from;
	  *nbytes = i_byte - from_byte;
	  return width;
	}
      if (ckd_add (&width, width, thiswidth))
	string_overflow ();
      i += chars;
      i_byte += bytes;
    }

  if (precision > 0)
    {
      *nchars = i - from;
      *nbytes = i_byte - from_byte;
    }

  return width;
}

DEFUN ("string-width", Fstring_width, Sstring_width, 1, 3, 0,
       doc: /* Return width of STRING in columns when displayed in the current buffer.
Width of STRING is measured by how many columns it will occupy on the screen.

Optional arguments FROM and TO specify the substring of STRING to
consider, and are interpreted as in `substring'.

Width of each character in STRING is generally taken according to
`char-width', but character compositions and the display table in
effect are taken into consideration.
Tabs in STRING are always assumed to occupy `tab-width' columns,
although they might take fewer columns depending on the column where
they begin on display.
The effect of faces and fonts, including fonts used for non-Latin and
other unusual characters, such as emoji, is ignored, as are display
properties and invisible text.

For these reasons, the results are just an approximation, especially
on GUI frames; for accurate dimensions of text as it will be
displayed, use `string-pixel-width' or `window-text-pixel-size'
instead.
usage: (string-width STRING &optional FROM TO)  */)
  (Lisp_Object str, Lisp_Object from, Lisp_Object to)
{
  Lisp_Object val;
  ptrdiff_t ifrom, ito;

  CHECK_STRING (str);
  validate_subarray (str, from, to, SCHARS (str), &ifrom, &ito);
  XSETFASTINT (val, lisp_string_width (str, ifrom, ito, -1, NULL, NULL, true));
  return val;
}

/* Return the number of characters in the NBYTES bytes at PTR.
   This works by looking at the contents and checking for multibyte
   sequences while assuming that there's no invalid sequence.
   However, if the current buffer has enable-multibyte-characters =
   nil, we treat each byte as a character.  */

ptrdiff_t
chars_in_text (const unsigned char *ptr, ptrdiff_t nbytes)
{
  /* current_buffer is null at early stages of Emacs initialization.  */
  if (current_buffer == 0
      || NILP (BVAR (current_buffer, enable_multibyte_characters)))
    return nbytes;

  return multibyte_chars_in_text (ptr, nbytes);
}

/* Return the number of characters in the NBYTES bytes at PTR.
   This works by looking at the contents and checking for multibyte
   sequences while assuming that there's no invalid sequence.  It
   ignores enable-multibyte-characters.  */

ptrdiff_t
multibyte_chars_in_text (const unsigned char *ptr, ptrdiff_t nbytes)
{
  const unsigned char *endp = ptr + nbytes;
  ptrdiff_t chars = 0;

  while (ptr < endp)
    {
      int len = multibyte_length (ptr, endp, true, true);

      if (len == 0)
	emacs_abort ();
      ptr += len;
      chars++;
    }

  return chars;
}

/* Parse unibyte text at STR of LEN bytes as a multibyte text, count
   characters and bytes in it, and store them in *NCHARS and *NBYTES
   respectively.  On counting bytes, pay attention to that 8-bit
   characters not constructing a valid multibyte sequence are
   represented by 2-byte in a multibyte text.  */

void
parse_str_as_multibyte (const unsigned char *str, ptrdiff_t len,
			ptrdiff_t *nchars, ptrdiff_t *nbytes)
{
  const unsigned char *endp = str + len;
  ptrdiff_t chars = 0, bytes = 0;

  if (len >= MAX_MULTIBYTE_LENGTH)
    {
      const unsigned char *adjusted_endp = endp - (MAX_MULTIBYTE_LENGTH - 1);
      while (str < adjusted_endp)
	{
	  int n = multibyte_length (str, NULL, false, false);
	  if (0 < n)
	    str += n, bytes += n;
	  else
	    str++, bytes += 2;
	  chars++;
	}
    }
  while (str < endp)
    {
      int n = multibyte_length (str, endp, true, false);
      if (0 < n)
	str += n, bytes += n;
      else
	str++, bytes += 2;
      chars++;
    }

  *nchars = chars;
  *nbytes = bytes;
  return;
}

/* Arrange unibyte text at STR of NBYTES bytes as a multibyte text.
   It actually converts only such 8-bit characters that don't construct
   a multibyte sequence to multibyte forms of raw bytes.  If NCHARS
   is nonzero, set *NCHARS to the number of characters in the text.
   It is assured that we can use LEN bytes at STR as a work
   area and that is enough.  Return the number of bytes of the
   resulting text.  */

ptrdiff_t
str_as_multibyte (unsigned char *str, ptrdiff_t len, ptrdiff_t nbytes,
		  ptrdiff_t *nchars)
{
  unsigned char *p = str, *endp = str + nbytes;
  unsigned char *to;
  ptrdiff_t chars = 0;

  if (nbytes >= MAX_MULTIBYTE_LENGTH)
    {
      unsigned char *adjusted_endp = endp - (MAX_MULTIBYTE_LENGTH - 1);
      while (p < adjusted_endp)
	{
	  int n = multibyte_length (p, NULL, false, false);
	  if (n <= 0)
	    break;
	  p += n, chars++;
	}
    }
  while (true)
    {
      int n = multibyte_length (p, endp, true, false);
      if (n <= 0)
	break;
      p += n, chars++;
    }
  if (nchars)
    *nchars = chars;
  if (p == endp)
    return nbytes;

  to = p;
  nbytes = endp - p;
  endp = str + len;
  memmove (endp - nbytes, p, nbytes);
  p = endp - nbytes;

  if (nbytes >= MAX_MULTIBYTE_LENGTH)
    {
      unsigned char *adjusted_endp = endp - (MAX_MULTIBYTE_LENGTH - 1);
      while (p < adjusted_endp)
	{
	  int n = multibyte_length (p, NULL, false, false);
	  if (0 < n)
	    {
	      while (n--)
		*to++ = *p++;
	    }
	  else
	    {
	      int c = *p++;
	      c = BYTE8_TO_CHAR (c);
	      to += CHAR_STRING (c, to);
	    }
	}
      chars++;
    }
  while (p < endp)
    {
      int n = multibyte_length (p, endp, true, false);
      if (0 < n)
	{
	  while (n--)
	    *to++ = *p++;
	}
      else
	{
	  int c = *p++;
	  c = BYTE8_TO_CHAR (c);
	  to += CHAR_STRING (c, to);
	}
      chars++;
    }
  if (nchars)
    *nchars = chars;
  return (to - str);
}

/* Parse unibyte string at STR of LEN bytes, and return the number of
   bytes it may occupy when converted to multibyte string by
   `str_to_multibyte'.  */

ptrdiff_t
count_size_as_multibyte (const unsigned char *str, ptrdiff_t len)
{
  /* Count the number of non-ASCII (raw) bytes, since they will occupy
     two bytes in a multibyte string.  */
  ptrdiff_t nonascii = 0;
  for (ptrdiff_t i = 0; i < len; i++)
    nonascii += str[i] >> 7;
  ptrdiff_t bytes;
  if (ckd_add (&bytes, len, nonascii))
    string_overflow ();
  return bytes;
}


/* Convert unibyte text at SRC of NCHARS chars to a multibyte text
   at DST, that contains the same single-byte characters.
   Return the number of bytes written at DST.  */
ptrdiff_t
str_to_multibyte (unsigned char *dst, const unsigned char *src,
		  ptrdiff_t nchars)
{
  unsigned char *d = dst;
  for (ptrdiff_t i = 0; i < nchars; i++)
    {
      unsigned char c = src[i];
      if (c <= 0x7f)
	*d++ = c;
      else
	{
	  *d++ = 0xc0 + ((c >> 6) & 1);
	  *d++ = 0x80 + (c & 0x3f);
	}
    }
  return d - dst;
}

/* Arrange multibyte text at STR of LEN bytes as a unibyte text.  It
   actually converts characters in the range 0x80..0xFF to
   unibyte.  */

ptrdiff_t
str_as_unibyte (unsigned char *str, ptrdiff_t bytes)
{
  const unsigned char *p = str, *endp = str + bytes;
  unsigned char *to;
  int c, len;

  while (p < endp)
    {
      c = *p;
      len = BYTES_BY_CHAR_HEAD (c);
      if (CHAR_BYTE8_HEAD_P (c))
	break;
      p += len;
    }
  to = str + (p - str);
  while (p < endp)
    {
      c = *p;
      len = BYTES_BY_CHAR_HEAD (c);
      if (CHAR_BYTE8_HEAD_P (c))
	{
	  c = string_char_advance (&p);
	  *to++ = CHAR_TO_BYTE8 (c);
	}
      else
	{
	  while (len--) *to++ = *p++;
	}
    }
  return (to - str);
}

static ptrdiff_t
string_count_byte8 (Lisp_Object string)
{
  bool multibyte = STRING_MULTIBYTE (string);
  ptrdiff_t nbytes = SBYTES (string);
  unsigned char *p = SDATA (string);
  unsigned char *pend = p + nbytes;
  ptrdiff_t count = 0;
  int c, len;

  if (multibyte)
    while (p < pend)
      {
	c = *p;
	len = BYTES_BY_CHAR_HEAD (c);

	if (CHAR_BYTE8_HEAD_P (c))
	  count++;
	p += len;
      }
  else
    while (p < pend)
      {
	if (*p++ >= 0x80)
	  count++;
      }
  return count;
}


Lisp_Object
string_escape_byte8 (Lisp_Object string)
{
  ptrdiff_t nchars = SCHARS (string);
  ptrdiff_t nbytes = SBYTES (string);
  bool multibyte = STRING_MULTIBYTE (string);
  ptrdiff_t byte8_count;
  ptrdiff_t thrice_byte8_count, uninit_nchars, uninit_nbytes;
  const unsigned char *src, *src_end;
  unsigned char *dst;
  Lisp_Object val;
  int c, len;

  if (multibyte && nchars == nbytes)
    return string;

  byte8_count = string_count_byte8 (string);

  if (byte8_count == 0)
    return string;

  if (ckd_mul (&thrice_byte8_count, byte8_count, 3))
    string_overflow ();

  if (multibyte)
    {
      /* Convert 2-byte sequence of byte8 chars to 4-byte octal.  */
      if (ckd_add (&uninit_nchars, nchars, thrice_byte8_count)
	  || ckd_add (&uninit_nbytes, nbytes, 2 * byte8_count))
	string_overflow ();
      val = make_uninit_multibyte_string (uninit_nchars, uninit_nbytes);
    }
  else
    {
      /* Convert 1-byte sequence of byte8 chars to 4-byte octal.  */
      if (ckd_add (&uninit_nbytes, thrice_byte8_count, nbytes))
	string_overflow ();
      val = make_uninit_string (uninit_nbytes);
    }

  src = SDATA (string);
  src_end = src + nbytes;
  dst = SDATA (val);
  if (multibyte)
    while (src < src_end)
      {
	c = *src;
	len = BYTES_BY_CHAR_HEAD (c);

	if (CHAR_BYTE8_HEAD_P (c))
	  {
	    c = string_char_advance (&src);
	    c = CHAR_TO_BYTE8 (c);
	    dst += sprintf ((char *) dst, "\\%03o", c + 0u);
	  }
	else
	  while (len--) *dst++ = *src++;
      }
  else
    while (src < src_end)
      {
	c = *src++;
	if (c >= 0x80)
	  dst += sprintf ((char *) dst, "\\%03o", c + 0u);
	else
	  *dst++ = c;
      }
  return val;
}


DEFUN ("string", Fstring, Sstring, 0, MANY, 0,
       doc: /*
Concatenate all the argument characters and make the result a string.
usage: (string &rest CHARACTERS)  */)
  (ptrdiff_t n, Lisp_Object *args)
{
  ptrdiff_t nbytes = 0;
  for (ptrdiff_t i = 0; i < n; i++)
    {
      CHECK_CHARACTER (args[i]);
      nbytes += CHAR_BYTES (XFIXNUM (args[i]));
    }
  if (nbytes == n)
    return Funibyte_string (n, args);
  Lisp_Object str = make_uninit_multibyte_string (n, nbytes);
  unsigned char *p = SDATA (str);
  for (ptrdiff_t i = 0; i < n; i++)
    {
      eassume (CHARACTERP (args[i]));
      int c = XFIXNUM (args[i]);
      p += CHAR_STRING (c, p);
    }
  return str;
}

DEFUN ("unibyte-string", Funibyte_string, Sunibyte_string, 0, MANY, 0,
       doc: /* Concatenate all the argument bytes and make the result a unibyte string.
usage: (unibyte-string &rest BYTES)  */)
  (ptrdiff_t n, Lisp_Object *args)
{
  Lisp_Object str = make_uninit_string (n);
  unsigned char *p = SDATA (str);
  for (ptrdiff_t i = 0; i < n; i++)
    *p++ = check_integer_range (args[i], 0, 255);
  return str;
}

DEFUN ("char-resolve-modifiers", Fchar_resolve_modifiers,
       Schar_resolve_modifiers, 1, 1, 0,
       doc: /* Resolve modifiers in the character CHAR.
The value is a character with modifiers resolved into the character
code.  Unresolved modifiers are kept in the value.
usage: (char-resolve-modifiers CHAR)  */)
  (Lisp_Object character)
{
  EMACS_INT c;

  CHECK_FIXNUM (character);
  c = XFIXNUM (character);
  return make_fixnum (char_resolve_modifier_mask (c));
}

DEFUN ("get-byte", Fget_byte, Sget_byte, 0, 2, 0,
       doc: /* Return a byte value of a character at point.
Optional 1st arg POSITION, if non-nil, is a position of a character to get
a byte value.
Optional 2nd arg STRING, if non-nil, is a string of which first
character is a target to get a byte value.  In this case, POSITION, if
non-nil, is an index of a target character in the string.

If the current buffer (or STRING) is multibyte, and the target
character is not ASCII nor 8-bit character, an error is signaled.  */)
  (Lisp_Object position, Lisp_Object string)
{
  int c;
  ptrdiff_t pos;
  unsigned char *p;

  if (NILP (string))
    {
      if (NILP (position))
	{
	  p = PT_ADDR;
	}
      else
	{
	  EMACS_INT fixed_pos = fix_position (position);
	  if (! (BEGV <= fixed_pos && fixed_pos < ZV))
	    args_out_of_range_3 (position, make_fixnum (BEGV), make_fixnum (ZV));
	  pos = fixed_pos;
	  p = CHAR_POS_ADDR (pos);
	}
      if (NILP (BVAR (current_buffer, enable_multibyte_characters)))
	return make_fixnum (*p);
    }
  else
    {
      CHECK_STRING (string);
      if (NILP (position))
	{
	  p = SDATA (string);
	}
      else
	{
	  CHECK_FIXNAT (position);
	  if (XFIXNUM (position) >= SCHARS (string))
	    args_out_of_range (string, position);
	  pos = XFIXNAT (position);
	  p = SDATA (string) + string_char_to_byte (string, pos);
	}
      if (! STRING_MULTIBYTE (string))
	return make_fixnum (*p);
    }
  c = STRING_CHAR (p);
  if (CHAR_BYTE8_P (c))
    c = CHAR_TO_BYTE8 (c);
  else if (! ASCII_CHAR_P (c))
    error ("Not an ASCII nor an 8-bit character: %d", c);
  return make_fixnum (c);
}

/* Return true if C is an alphabetic character.  */
bool
alphabeticp (int c)
{
  Lisp_Object category = CHAR_TABLE_REF (Vunicode_category_table, c);
  if (! FIXNUMP (category))
    return false;
  EMACS_INT gen_cat = XFIXNUM (category);

  /* See UTS #18.  There are additional characters that should be
     here, those designated as Other_uppercase, Other_lowercase,
     and Other_alphabetic; FIXME.  */
  return (gen_cat == UNICODE_CATEGORY_Lu
	  || gen_cat == UNICODE_CATEGORY_Ll
	  || gen_cat == UNICODE_CATEGORY_Lt
	  || gen_cat == UNICODE_CATEGORY_Lm
	  || gen_cat == UNICODE_CATEGORY_Lo
	  || gen_cat == UNICODE_CATEGORY_Mn
	  || gen_cat == UNICODE_CATEGORY_Mc
	  || gen_cat == UNICODE_CATEGORY_Me
	  || gen_cat == UNICODE_CATEGORY_Nl);
}

/* Return true if C is an alphabetic or decimal-number character.  */
bool
alphanumericp (int c)
{
  Lisp_Object category = CHAR_TABLE_REF (Vunicode_category_table, c);
  if (! FIXNUMP (category))
    return false;
  EMACS_INT gen_cat = XFIXNUM (category);

  /* See UTS #18.  Same comment as for alphabeticp applies.  FIXME. */
  return (gen_cat == UNICODE_CATEGORY_Lu
	  || gen_cat == UNICODE_CATEGORY_Ll
	  || gen_cat == UNICODE_CATEGORY_Lt
	  || gen_cat == UNICODE_CATEGORY_Lm
	  || gen_cat == UNICODE_CATEGORY_Lo
	  || gen_cat == UNICODE_CATEGORY_Mn
	  || gen_cat == UNICODE_CATEGORY_Mc
	  || gen_cat == UNICODE_CATEGORY_Me
	  || gen_cat == UNICODE_CATEGORY_Nl
	  || gen_cat == UNICODE_CATEGORY_Nd);
}

/* Return true if C is a graphic character.  */
bool
graphicp (int c)
{
  Lisp_Object category = CHAR_TABLE_REF (Vunicode_category_table, c);
  if (! FIXNUMP (category))
    return false;
  EMACS_INT gen_cat = XFIXNUM (category);

  /* See UTS #18.  */
  return (!(gen_cat == UNICODE_CATEGORY_Zs /* space separator */
	    || gen_cat == UNICODE_CATEGORY_Zl /* line separator */
	    || gen_cat == UNICODE_CATEGORY_Zp /* paragraph separator */
	    || gen_cat == UNICODE_CATEGORY_Cc /* control */
	    || gen_cat == UNICODE_CATEGORY_Cs /* surrogate */
	    || gen_cat == UNICODE_CATEGORY_Cn)); /* unassigned */
}

/* Return true if C is a printable character.  */
bool
printablep (int c)
{
  Lisp_Object category = CHAR_TABLE_REF (Vunicode_category_table, c);
  if (! FIXNUMP (category))
    return false;
  EMACS_INT gen_cat = XFIXNUM (category);

  /* See UTS #18.  */
  return (!(gen_cat == UNICODE_CATEGORY_Cc /* control */
	    || gen_cat == UNICODE_CATEGORY_Cs /* surrogate */
	    || gen_cat == UNICODE_CATEGORY_Cn)); /* unassigned */
}

/* Return true if C is graphic character that can be printed independently.  */
bool
graphic_base_p (int c)
{
  Lisp_Object category = CHAR_TABLE_REF (Vunicode_category_table, c);
  if (! FIXNUMP (category))
    return false;
  EMACS_INT gen_cat = XFIXNUM (category);

  return (!(gen_cat == UNICODE_CATEGORY_Mn       /* mark, nonspacing */
            || gen_cat == UNICODE_CATEGORY_Mc    /* mark, combining */
            || gen_cat == UNICODE_CATEGORY_Me    /* mark, enclosing */
            || gen_cat == UNICODE_CATEGORY_Zs    /* separator, space */
            || gen_cat == UNICODE_CATEGORY_Zl    /* separator, line */
            || gen_cat == UNICODE_CATEGORY_Zp    /* separator, paragraph */
            || gen_cat == UNICODE_CATEGORY_Cc    /* other, control */
            || gen_cat == UNICODE_CATEGORY_Cs    /* other, surrogate */
            || gen_cat == UNICODE_CATEGORY_Cf    /* other, format */
            || gen_cat == UNICODE_CATEGORY_Cn)); /* other, unassigned */
}

/* Return true if C is a horizontal whitespace character, as defined
   by https://www.unicode.org/reports/tr18/tr18-19.html#blank.  */
bool
blankp (int c)
{
  Lisp_Object category = CHAR_TABLE_REF (Vunicode_category_table, c);
  if (! FIXNUMP (category))
    return false;

  return XFIXNUM (category) == UNICODE_CATEGORY_Zs; /* separator, space */
}

/* hexdigit[C] is one greater than C's numeric value if C is a
   hexadecimal digit, zero otherwise.  */
signed char const hexdigit[UCHAR_MAX + 1] =
  {
    ['0'] = 1 + 0, ['1'] = 1 + 1, ['2'] = 1 + 2, ['3'] = 1 + 3, ['4'] = 1 + 4,
    ['5'] = 1 + 5, ['6'] = 1 + 6, ['7'] = 1 + 7, ['8'] = 1 + 8, ['9'] = 1 + 9,
    ['A'] = 1 + 10, ['B'] = 1 + 11, ['C'] = 1 + 12,
    ['D'] = 1 + 13, ['E'] = 1 + 14, ['F'] = 1 + 15,
    ['a'] = 1 + 10, ['b'] = 1 + 11, ['c'] = 1 + 12,
    ['d'] = 1 + 13, ['e'] = 1 + 14, ['f'] = 1 + 15
  };

void
syms_of_character (void)
{
  DEFSYM (Qcharacterp, "characterp");
  DEFSYM (Qauto_fill_chars, "auto-fill-chars");

  staticpro (&Vchar_unify_table);
  Vchar_unify_table = Qnil;

  defsubr (&Smax_char);
  defsubr (&Scharacterp);
  defsubr (&Sunibyte_char_to_multibyte);
  defsubr (&Smultibyte_char_to_unibyte);
  defsubr (&Schar_width);
  defsubr (&Sstring_width);
  defsubr (&Sstring);
  defsubr (&Sunibyte_string);
  defsubr (&Schar_resolve_modifiers);
  defsubr (&Sget_byte);

  DEFVAR_LISP ("translation-table-vector",  Vtranslation_table_vector,
	       doc: /*
Vector recording all translation tables ever defined.
Each element is a pair (SYMBOL . TABLE) relating the table to the
symbol naming it.  The ID of a translation table is an index into this vector.  */);
  Vtranslation_table_vector = make_nil_vector (16);

  DEFVAR_LISP ("auto-fill-chars", Vauto_fill_chars,
	       doc: /*
A char-table for characters which invoke auto-filling.
Such characters have the value t in this table.  */);
  Vauto_fill_chars = Fmake_char_table (Qauto_fill_chars, Qnil);
  CHAR_TABLE_SET (Vauto_fill_chars, ' ', Qt);
  CHAR_TABLE_SET (Vauto_fill_chars, '\n', Qt);

  DEFVAR_LISP ("char-width-table", Vchar_width_table,
	       doc: /*
A char-table for width (columns) of each character.  */);
  Vchar_width_table = Fmake_char_table (Qnil, make_fixnum (1));
  char_table_set_range (Vchar_width_table, 0x80, 0x9F, make_fixnum (4));
  char_table_set_range (Vchar_width_table, MAX_5_BYTE_CHAR + 1, MAX_CHAR,
			make_fixnum (4));

  DEFVAR_LISP ("ambiguous-width-chars", Vambiguous_width_chars,
	       doc: /*
A char-table for characters whose width (columns) can be 1 or 2.

The actual width depends on the language-environment and on the
value of `cjk-ambiguous-chars-are-wide'.  */);
  Vambiguous_width_chars = Fmake_char_table (Qnil, Qnil);

  DEFVAR_LISP ("printable-chars", Vprintable_chars,
	       doc: /* A char-table for printable characters.
Such characters have the value t in this table.  */);
  Vprintable_chars = Fmake_char_table (Qnil, Qnil);
  Fset_char_table_range (Vprintable_chars,
			 Fcons (make_fixnum (32), make_fixnum (126)), Qt);
  Fset_char_table_range (Vprintable_chars,
			 Fcons (make_fixnum (160),
				make_fixnum (MAX_5_BYTE_CHAR)), Qt);

  DEFVAR_LISP ("char-script-table", Vchar_script_table,
	       doc: /* Char table of script symbols.
It has one extra slot whose value is a list of script symbols.  */);

  DEFSYM (Qchar_script_table, "char-script-table");
  Fput (Qchar_script_table, Qchar_table_extra_slots, make_fixnum (1));
  Vchar_script_table = Fmake_char_table (Qchar_script_table, Qnil);

  DEFVAR_LISP ("script-representative-chars", Vscript_representative_chars,
	       doc: /* Alist of scripts vs the representative characters.
Each element is a cons (SCRIPT . CHARS).
SCRIPT is a symbol representing a script or a subgroup of a script.
CHARS is a list or a vector of characters.
If it is a list, all characters in the list are necessary for supporting SCRIPT.
If it is a vector, one of the characters in the vector is necessary.
This variable is used to find a font for a specific script.  */);
  Vscript_representative_chars = Qnil;

  DEFVAR_LISP ("unicode-category-table", Vunicode_category_table,
	       doc: /* Char table of Unicode's "General Category".
All Unicode characters have one of the following values (symbol):
  Lu, Ll, Lt, Lm, Lo, Mn, Mc, Me, Nd, Nl, No, Pc, Pd, Ps, Pe, Pi, Pf, Po,
  Sm, Sc, Sk, So, Zs, Zl, Zp, Cc, Cf, Cs, Co, Cn
See The Unicode Standard for the meaning of those values.  */);
  /* The correct char-table is setup in characters.el.  */
  Vunicode_category_table = Qnil;
}
