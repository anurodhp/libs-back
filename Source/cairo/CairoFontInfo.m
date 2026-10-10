/*
   CairoFontInfo.m
 
   Copyright (C) 2003 Free Software Foundation, Inc.

   August 31, 2003
   Written by Banlu Kemiyatorn <object at gmail dot com>
   Base on original code of Alex Malmberg

   This file is part of GNUstep.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	 See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; see the file COPYING.LIB.
   If not, see <http://www.gnu.org/licenses/> or write to the 
   Free Software Foundation, 51 Franklin Street, Fifth Floor, 
   Boston, MA 02110-1301, USA.
*/

#include "GNUstepBase/Unicode.h"
#include <AppKit/NSAffineTransform.h>
#include <AppKit/NSBezierPath.h>
#include "cairo/CairoFontInfo.h"
#include "cairo/CairoFontEnumerator.h"

#include <math.h>
#include <cairo-ft.h>

#include FT_FREETYPE_H
#include FT_SFNT_NAMES_H
#include FT_TRUETYPE_TABLES_H
#include FT_TYPE1_TABLES_H
#include <fontconfig/fontconfig.h>
#include <fontconfig/fcfreetype.h>

void set_font_options(cairo_font_options_t *options)
{
  NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
  cairo_hint_metrics_t metrics = CAIRO_HINT_METRICS_ON;
  cairo_hint_style_t   style = CAIRO_HINT_STYLE_NONE;
  int hinting = [ud integerForKey: @"GSFontHinting"];
  float scale = [ud floatForKey: @"GSScaleFactor"];
  int subpixel = 0;

  if (hinting == 0) 
    {
      /*
       * This could be on purpose or a missing value.
       * In the later case use the defaults.
       */
      if (nil == [ud objectForKey: @"GSFontHinting"])
        {
          /*
           * Default hinting to off if scale is set to something other than 1.0. As
           * hinting + scaling breaks assumptions about glyph advancement made in gui.
           */
          if (scale == 0.0f || scale == 1.0f)
            {
              hinting = 33;
            }
          else
            {
              hinting = 17;
            }
        }
    }
  
  /*
   * This part is only here to debug disabling the use of hinting for
   * metrics, because doing so causes menus to get cut off on the right.
   */
  switch (hinting >> 4)
    {
    case 0:
      metrics = CAIRO_HINT_METRICS_DEFAULT;
      break;
    case 1:
      metrics = CAIRO_HINT_METRICS_OFF;
      break;
    case 2:
      metrics = CAIRO_HINT_METRICS_ON;
      break;
    }
  
  switch (hinting & 0x0f)
    {
    case 0:
      style = CAIRO_HINT_STYLE_DEFAULT;
      break;
    case 1:
      style = CAIRO_HINT_STYLE_NONE;
      break;
    case 2:
      style = CAIRO_HINT_STYLE_SLIGHT;
      break;
    case 3:
      style = CAIRO_HINT_STYLE_MEDIUM;
      break;
    case 4:
      style = CAIRO_HINT_STYLE_FULL;
      break;
    }
  
  cairo_font_options_set_hint_metrics(options, metrics);
  cairo_font_options_set_hint_style(options, style);

  if ((subpixel = [ud integerForKey: @"back-art-subpixel-text"]))
    {
      cairo_font_options_set_antialias(options, CAIRO_ANTIALIAS_SUBPIXEL);

      if (subpixel == 2)
        {
          cairo_font_options_set_subpixel_order(options, CAIRO_SUBPIXEL_ORDER_BGR);
        }
      else
        {
          cairo_font_options_set_subpixel_order(options, CAIRO_SUBPIXEL_ORDER_RGB);
        }
    }
}

@implementation CairoFontInfo 

- (BOOL) setupAttributes
{
  cairo_font_extents_t font_extents;
  cairo_font_face_t *face;
  cairo_matrix_t font_matrix;
  cairo_matrix_t ctm;
  cairo_font_options_t *options;

  if (![super setupAttributes])
    {
      return NO;
    }

  /* setting GSFontInfo:
   * xHeight, pix_width, pix_height
   */
  cairo_matrix_init(&font_matrix, matrix[0], matrix[1], -matrix[2],
                    matrix[3], matrix[4], matrix[5]);
  //cairo_matrix_scale(&font_matrix, 0.9, 0.9);
  cairo_matrix_init_identity(&ctm);

  face = [_faceInfo fontFace];
  if (!face)
    {
      return NO;
    }

  // Get default font options
  options = cairo_font_options_create();
  if (cairo_font_options_status(options) != CAIRO_STATUS_SUCCESS)
    {
      return NO;
    }
  
  set_font_options(options);

  _scaled = cairo_scaled_font_create(face, &font_matrix, &ctm, options);
  cairo_font_options_destroy(options);
  if (cairo_scaled_font_status(_scaled) != CAIRO_STATUS_SUCCESS)
    {
      return NO;
    }

  cairo_scaled_font_extents(_scaled, &font_extents);
  if (cairo_scaled_font_status(_scaled) != CAIRO_STATUS_SUCCESS)
    {
      return NO;
    }

  ascender = font_extents.ascent;
  descender = -font_extents.descent;
  xHeight = ascender * 0.6;
  lineHeight = font_extents.height;
  maximumAdvancement = NSMakeSize(font_extents.max_x_advance, 
                                  font_extents.max_y_advance);
  fontBBox = NSMakeRect(0, descender, 
                        maximumAdvancement.width, ascender - descender);
/*
  NSLog(@"Font matrix (%g, %g, %g, %g, %g, %g) type %d", 
        matrix[0], matrix[1], matrix[2],
        matrix[3], matrix[4], matrix[5], cairo_scaled_font_get_type(_scaled));
	NSLog(@"(%@) h=%g  a=%g d=%g  max=(%g %g)  (%g %g)+(%g %g)\n", fontName,
		xHeight, ascender, descender,
		maximumAdvancement.width, maximumAdvancement.height,
		fontBBox.origin.x, fontBBox.origin.y,
		fontBBox.size.width, fontBBox.size.height);
*/

  return YES;
}

- (id) initWithFontName: (NSString *)name 
                 matrix: (const CGFloat *)fmatrix 
             screenFont: (BOOL)p_screenFont
{
  self = [super init];
  if (!self)
    return nil;

  _screenFont = p_screenFont;
  fontName = [name copy];
  memcpy(matrix, fmatrix, sizeof(matrix));

  if (_screenFont)
    {
      /* Round up; makes the text more legible. */
      matrix[0] = ceil(matrix[0]);
      if (matrix[3] < 0.0)
        matrix[3] = floor(matrix[3]);
      else
        matrix[3] = ceil(matrix[3]);
    }

  if (![self setupAttributes])
    {
      RELEASE(self);
      return nil;
    }

  return self;
}

- (void) dealloc
{
  RELEASE(_fallbacks);
  if (_scaled)
    {
      cairo_scaled_font_destroy(_scaled);
    }
  [super dealloc];
}

- (BOOL) _ownsGlyph: (NSGlyph)glyph
{
  BOOL val = NO;

  if (_scaled)
    {
      FT_Face face = cairo_ft_scaled_font_lock_face(_scaled);
      if (FT_Get_Char_Index (face, glyph) != 0)
	{
	  val = YES;
	}

      cairo_ft_scaled_font_unlock_face(_scaled);
    }
  return val;
}

/* Fonts tried, in order, for a character the requested font lacks.  GSFontFallbacks (user default, array of
 * font names) replaces the list.  FCFontEnumerator looks names up
 * exactly, so an unknown name just yields no face.  The defaults are the
 * fonts the image ships (iokit build_fonts.sh). */
static NSArray *
_fallback_names(void)
{
  NSArray *a = [[NSUserDefaults standardUserDefaults]
                 arrayForKey: @"GSFontFallbacks"];

  if (a)
    return a;
  return [NSArray arrayWithObjects:
    @"DejaVuSans", @"NotoSansCJKsc-Regular", @"NotoSansCJKjp-Regular",
    @"NotoSansCJKkr-Regular", @"NotoEmoji-Regular", @"Unifont", nil];
}

- (CairoFontInfo *) _fallbackForGlyph: (NSGlyph)glyph
{
  NSUInteger i, n;
  NSArray *names;

  if (_isFallback)
    return nil;

  if (!_fallbacks)
    {
      /* One face per name, NSNull for the ones the system does not have.
       * Built once per font. */
      names = _fallback_names();
      _fallbacks = [[NSMutableArray alloc] init];
      for (i = 0; i < [names count]; i++)
        {
          NSString *name = [names objectAtIndex: i];
          CairoFontInfo *f = [[CairoFontInfo alloc] initWithFontName: name
                                                             matrix: matrix
                                                         screenFont: _screenFont];

          if (f)
            {
              f->_isFallback = YES;
              [_fallbacks addObject: f];
              RELEASE(f);
            }
          else
            {
              [_fallbacks addObject: [NSNull null]];
            }
        }
    }

  n = [_fallbacks count];
  for (i = 0; i < n; i++)
    {
      CairoFontInfo *f = [_fallbacks objectAtIndex: i];

      if ((id)f != [NSNull null] && [f _ownsGlyph: glyph])
        {
          return f;
        }
    }
  return nil;
}

- (BOOL) glyphIsEncoded: (NSGlyph)glyph
{
  if ([self _ownsGlyph: glyph])
    return YES;
  if (glyph < 0x80)
    return NO;
  return [self _fallbackForGlyph: glyph] != nil;
}

/* The scaled font that draws this glyph: ours, else a fallback's. */
- (cairo_scaled_font_t *) _scaledForGlyph: (NSGlyph)glyph
{
  if (glyph >= 0x80 && ![self _ownsGlyph: glyph])
    {
      CairoFontInfo *f = [self _fallbackForGlyph: glyph];

      if (f)
        return f->_scaled;
    }
  return _scaled;
}

- (NSGlyph) glyphWithName: (NSString *)glyphName
{
  NSGlyph val = NSNullGlyph;
  FT_String *name = (FT_String *)[glyphName UTF8String];

  if (_scaled)
    {
      FT_Face face = cairo_ft_scaled_font_lock_face(_scaled);
      if (FT_Has_PS_Glyph_Names(face))
	{
	  val = (NSGlyph) FT_Get_Name_Index(face, name);
	}

      cairo_ft_scaled_font_unlock_face(_scaled);
    }

  return val;
}

/* Glyphs are Unicode code points here, so they can lie above U+FFFF; a
 * unichar buffer would truncate them to 16 bits.  Encode one as UTF-8,
 * return the byte count (0 for an invalid code point). */
static int
_utf8_for_NSGlyph(NSGlyph g, char *out)
{
  if (g < 0x80)
    {
      out[0] = g;
      return 1;
    }
  if (g < 0x800)
    {
      out[0] = 0xc0 | (g >> 6);
      out[1] = 0x80 | (g & 0x3f);
      return 2;
    }
  if (g >= 0xd800 && g <= 0xdfff)
    return 0;
  if (g < 0x10000)
    {
      out[0] = 0xe0 | (g >> 12);
      out[1] = 0x80 | ((g >> 6) & 0x3f);
      out[2] = 0x80 | (g & 0x3f);
      return 3;
    }
  if (g <= 0x10ffff)
    {
      out[0] = 0xf0 | (g >> 18);
      out[1] = 0x80 | ((g >> 12) & 0x3f);
      out[2] = 0x80 | ((g >> 6) & 0x3f);
      out[3] = 0x80 | (g & 0x3f);
      return 4;
    }
  return 0;
}

/* UTF-8 for count glyphs; str must hold 4 * count + 1 bytes. */
static void
_utf8_for_NSGlyphs(const NSGlyph *glyphs, int count, char *str)
{
  int i, n = 0;

  for (i = 0; i < count; i++)
    n += _utf8_for_NSGlyph(glyphs[i], str + n);
  str[n] = 0;
}

static
BOOL _cairo_extents_for_NSGlyph(cairo_scaled_font_t *scaled_font, NSGlyph glyph,
                                cairo_text_extents_t *ctext)
{
  char str[5];

  _utf8_for_NSGlyphs(&glyph, 1, str);

  cairo_scaled_font_text_extents(scaled_font, str, ctext);
  return cairo_scaled_font_status(scaled_font) == CAIRO_STATUS_SUCCESS;
}

- (NSSize) advancementForGlyph: (NSGlyph)glyph
{
  cairo_text_extents_t ctext;

  if (_cachedSizes)
    {
      int entry = glyph % _cacheSize;

      if (_cachedGlyphs[entry] == glyph)
        {
          return _cachedSizes[entry];
        }
      
      if (_cairo_extents_for_NSGlyph([self _scaledForGlyph: glyph], glyph, &ctext))
        {
          _cachedGlyphs[entry] = glyph;
          _cachedSizes[entry] = NSMakeSize(ctext.x_advance, ctext.y_advance);
          
          return _cachedSizes[entry];
        }
    }
  else
    {
      if (_cairo_extents_for_NSGlyph([self _scaledForGlyph: glyph], glyph, &ctext))
        {
          return NSMakeSize(ctext.x_advance, ctext.y_advance);
        }
    }

  return NSZeroSize;
}

- (NSRect) boundingRectForGlyph: (NSGlyph)glyph
{
  cairo_text_extents_t ctext;

  if (_cairo_extents_for_NSGlyph([self _scaledForGlyph: glyph], glyph, &ctext))
    {
      return NSMakeRect(ctext.x_bearing, ctext.y_bearing,
                        ctext.width, ctext.height);
    }

  return NSZeroRect;
}

- (NSString *) displayName
{
	return [_faceInfo displayName];
}


- (CGFloat) widthOfString: (NSString *)string
{
  cairo_text_extents_t ctext;

  if (!string)
    {
      return 0.0;
    }

  cairo_scaled_font_text_extents(_scaled, [string UTF8String], &ctext);
  if (cairo_scaled_font_status(_scaled) == CAIRO_STATUS_SUCCESS)
    {
      return ctext.width;
    }

  return 0.0;
}

- (void) appendBezierPathWithGlyphs: (NSGlyph *)glyphs 
                              count: (int)length 
                       toBezierPath: (NSBezierPath *)path
{
  cairo_format_t format = CAIRO_FORMAT_ARGB32;
  cairo_surface_t *isurface;
  cairo_t *ct;
  int ix = 400;
  int iy = 400;
  unsigned char *cdata;
  int i;
  char str[4*length+1];
  cairo_status_t status;
  cairo_matrix_t font_matrix;

  _utf8_for_NSGlyphs(glyphs, length, str);

  cdata = malloc(sizeof(char) * 4 * ix * iy);
  if (!cdata)
    {
      NSLog(@"Could not allocate drawing space for glyphs");
      return;
    }

  isurface = cairo_image_surface_create_for_data(cdata, format, ix, iy, 4*ix);
  status = cairo_surface_status(isurface);
  if (status != CAIRO_STATUS_SUCCESS)
    {
      NSLog(@"Error while creating surface: %s", 
            cairo_status_to_string(status));
      cairo_surface_destroy(isurface);
      free(cdata);
      return;
    }
 
  ct = cairo_create(isurface);
  if (cairo_status(ct) != CAIRO_STATUS_SUCCESS)
    {
      NSLog(@"Error while creating context: %s", 
            cairo_status_to_string(cairo_status(ct)));
      cairo_destroy(ct);
      cairo_surface_destroy(isurface);
      free(cdata);
      return;
    }

  // Use flip matrix
  cairo_matrix_init(&font_matrix, matrix[0], matrix[1], matrix[2],
                    -matrix[3], matrix[4], matrix[5]);
  cairo_set_font_matrix(ct, &font_matrix);
  if (cairo_status(ct) != CAIRO_STATUS_SUCCESS)
    {
      NSLog(@"Error while setting font matrix: %s", 
            cairo_status_to_string(cairo_status(ct)));
      cairo_destroy(ct);
      cairo_surface_destroy(isurface);
      free(cdata);
      return;
    }

  cairo_set_font_face(ct, [_faceInfo fontFace]);
  if (cairo_status(ct) != CAIRO_STATUS_SUCCESS)
    {
      NSLog(@"Error while setting font face: %s", 
            cairo_status_to_string(cairo_status(ct)));
      cairo_destroy(ct);
      cairo_surface_destroy(isurface);
      free(cdata);
      return;
    }

  // Set font options from the scaled font
  // FIXME: Instead of setting the matrix, setting the face, and setting
  // the options, we should be using cairo_set_scaled_font().
  // But we have to deal with the flipped matrix here.
  {
    cairo_font_options_t *options = cairo_font_options_create();
    cairo_scaled_font_get_font_options(_scaled, options);
    cairo_set_font_options(ct, options);
    cairo_font_options_destroy(options);
  }
  if (cairo_status(ct) != CAIRO_STATUS_SUCCESS)
    {
      NSLog(@"Error while setting font options: %s", 
            cairo_status_to_string(cairo_status(ct)));
      cairo_destroy(ct);
      cairo_surface_destroy(isurface);
      free(cdata);
      return;
    }

  if ([path elementCount] > 0)
    {
      NSPoint p;

      p = [path currentPoint];
      cairo_move_to(ct, floorf(p.x), floorf(p.y));
    }

  cairo_text_path(ct, str);
  if (cairo_status(ct) == CAIRO_STATUS_SUCCESS)
     {
      cairo_path_t *cpath;
      cairo_path_data_t *data;
      
      cpath = cairo_copy_path(ct);
      
      for (i = 0; i < cpath->num_data; i += cpath->data[i].header.length) 
        {
          data = &cpath->data[i];
          switch (data->header.type) 
            {
              case CAIRO_PATH_MOVE_TO:
                [path moveToPoint: NSMakePoint(data[1].point.x, data[1].point.y)];
                break;
              case CAIRO_PATH_LINE_TO:
                [path lineToPoint: NSMakePoint(data[1].point.x, data[1].point.y)];
                break;
              case CAIRO_PATH_CURVE_TO:
                [path curveToPoint: NSMakePoint(data[3].point.x, data[3].point.y) 
                      controlPoint1: NSMakePoint(data[1].point.x, data[1].point.y)
                      controlPoint2: NSMakePoint(data[2].point.x, data[2].point.y)];
                break;
              case CAIRO_PATH_CLOSE_PATH:
                [path closePath];
                break;
            }
        }
      cairo_path_destroy(cpath);
    }
  cairo_destroy(ct);
  cairo_surface_destroy(isurface);
  free(cdata);
}

- (void) drawGlyphs: (const NSGlyph*)glyphs
             length: (int)length 
                 on: (cairo_t*)ct
{
  char str[4*length+1];

  int i = 0;

  while (i < length)
    {
      cairo_scaled_font_t *sf = [self _scaledForGlyph: glyphs[i]];
      int j = i + 1;

      while (j < length && [self _scaledForGlyph: glyphs[j]] == sf)
        j++;

      _utf8_for_NSGlyphs(glyphs + i, j - i, str);

      cairo_set_scaled_font(ct, sf);
      if (cairo_status(ct) != CAIRO_STATUS_SUCCESS)
        {
          NSLog(@"Error while setting scaled font: %s", 
                cairo_status_to_string(cairo_status(ct)));
          return;
        }

      cairo_show_text(ct, str);
      if (cairo_status(ct) != CAIRO_STATUS_SUCCESS)
        {
          NSLog(@"Error drawing string: '%s' for string %s", 
                cairo_status_to_string(cairo_status(ct)), str);
        }
      i = j;
    }
}

@end
