#include <AppKit/NSAttributedString.h>
#include <AppKit/NSParagraphStyle.h>
#include <AppKit/NSTextAttachment.h>
#include <AppKit/NSFont.h>
#include <Foundation/NSString.h>
#include <Foundation/NSRange.h>
#include "Parsers/rtfConsumer.h"

/*
 * function to return a character set containing characters that
 * separate words.
 */
static NSCharacterSet*
wordBreakCSet()
{
  static NSCharacterSet	*cset = nil;

  if (cset == nil)
    {
      NSMutableCharacterSet	*m = [NSMutableCharacterSet new];

      cset = [NSCharacterSet whitespaceAndNewlineCharacterSet];
      [m formUnionWithCharacterSet: cset];
      cset = [NSCharacterSet punctuationCharacterSet];
      [m formUnionWithCharacterSet: cset];
      cset = [NSCharacterSet controlCharacterSet];
      [m formUnionWithCharacterSet: cset];
      cset = [NSCharacterSet illegalCharacterSet];
      [m formUnionWithCharacterSet: cset];
      cset = [m copy];
      RELEASE(m);
    }
  return cset;
}

/*
 * function to return a character set containing characters that
 * are legal within words.
 */
static NSCharacterSet*
wordCSet()
{
  static NSCharacterSet	*cset = nil;

  if (cset == nil)
    {
      cset = [[wordBreakCSet() invertedSet] copy];
    }
  return cset;
}

/*
 * function to return a character set containing paragraph separators
 */
static NSCharacterSet*
paraBreakCSet()
{
  static NSCharacterSet	*cset = nil;

  if (cset == nil)
    {
      NSMutableCharacterSet	*m = [NSMutableCharacterSet new];

      /*
       * Build set with characters specified in MacOS-X documentation for
       * [NSAttributedString -fixParagraphStyleAttributeInRange:]
       */
      [m addCharactersInRange: NSMakeRange(0x000A, 1)];	/* CR */
      [m addCharactersInRange: NSMakeRange(0x000D, 1)];	/* LF */
      [m addCharactersInRange: NSMakeRange(0x2028, 1)];	/* line sep */
      [m addCharactersInRange: NSMakeRange(0x2029, 1)];	/* para sep */
      cset = [m copy];
      RELEASE(m);
    }
  return cset;
}

@implementation NSAttributedString (AppKit)

- (BOOL) containsAttachments
{
  // Currently there are no attachment in GNUstep.
  // FIXME.
  return NO;
}

- (NSDictionary*) fontAttributesInRange: (NSRange)range
{
  NSDictionary	*all;
  static SEL	sel = @selector(objectForKey:);
  IMP		objForKey;
  id		objects[8];
  id		keys[8];
  int		count = 0;

  if (range.location < 0 || NSMaxRange(range) > [self length])
    {
      [NSException raise: NSRangeException
		  format: @"RangeError in method -fontAttributesInRange:"];
    }
  all = [self attributesAtIndex: range.location
		 effectiveRange: &range];

  objForKey = [all methodForSelector: sel];

  keys[count] = NSFontAttributeName;
  objects[count] = (*objForKey)(all, sel, keys[count]);
  if (objects[count] != nil)
    count++;

  keys[count] = NSForegroundColorAttributeName;
  objects[count] = (*objForKey)(all, sel, keys[count]);
  if (objects[count] != nil)
    count++;

  keys[count] = NSBackgroundColorAttributeName;
  objects[count] = (*objForKey)(all, sel, keys[count]);
  if (objects[count] != nil)
    count++;

  keys[count] = NSUnderlineStyleAttributeName;
  objects[count] = (*objForKey)(all, sel, keys[count]);
  if (objects[count] != nil)
    count++;

  keys[count] = NSSuperscriptAttributeName;
  objects[count] = (*objForKey)(all, sel, keys[count]);
  if (objects[count] != nil)
    count++;

  keys[count] = NSBaselineOffsetAttributeName;
  objects[count] = (*objForKey)(all, sel, keys[count]);
  if (objects[count] != nil)
    count++;

  keys[count] = NSKernAttributeName;
  objects[count] = (*objForKey)(all, sel, keys[count]);
  if (objects[count] != nil)
    count++;

  keys[count] = NSLigatureAttributeName;
  objects[count] = (*objForKey)(all, sel, keys[count]);
  if (objects[count] != nil)
    count++;

  return [NSDictionary dictionaryWithObjects: objects
				     forKeys: keys
				       count: count];
}

- (NSDictionary*) rulerAttributesInRange: (NSRange)range
{
  id	style;

  if (range.location < 0 || NSMaxRange(range) > [self length])
    {
      [NSException raise: NSRangeException
		  format: @"RangeError in method -rulerAttributesInRange:"];
    }

  style = [self attribute: NSParagraphStyleAttributeName
		  atIndex: range.location
	   effectiveRange: &range];

  if (style)
    {
      return [NSDictionary dictionaryWithObject: style
					 forKey: NSParagraphStyleAttributeName];
    }
  return [NSDictionary dictionary];
}

- (unsigned) lineBreakBeforeIndex: (unsigned)location
                      withinRange: (NSRange)aRange
{
  NSScanner *tScanner;
  unsigned int sL;

  tScanner = [[NSScanner alloc] initWithString: [[self string]
	substringWithRange: aRange]];
  [tScanner scanUpToString: [NSText newlineString] intoString:NULL];
  sL = [tScanner scanLocation] + 2;

  [tScanner release];

  if (sL > aRange.length)
    return NSNotFound;
  else
    return sL;
}

- (NSRange) doubleClickAtIndex: (unsigned)location
{
  NSString	*str = [self string];
  unsigned	length = [str length];
  NSRange	scanRange;
  NSRange	startRange;
  NSRange	endRange;

  scanRange = NSMakeRange(0, location);
  startRange = [str rangeOfCharacterFromSet: wordBreakCSet()
				    options: NSBackwardsSearch|NSLiteralSearch
				      range: scanRange];
  scanRange = NSMakeRange(location, length - location);
  endRange = [str rangeOfCharacterFromSet: wordBreakCSet()
				  options: NSLiteralSearch
				    range: scanRange];
  if (startRange.length == 0)
    {
      location = 0;
    }
  else
    {
      location = startRange.location + startRange.length;
    }
  if (endRange.length == 0)
    {
      length = length - location;
    }
  else
    {
      length = endRange.location - location;
    }
  return NSMakeRange(location, length);
}

- (unsigned) nextWordFromIndex: (unsigned)location
		       forward: (BOOL)isForward
{
  if (isForward)
    {
      NSString	*str = [self string];
      unsigned	length = [str length];
      NSRange	range;

      range = NSMakeRange(location, length - location);
      range = [str rangeOfCharacterFromSet: wordBreakCSet()
				   options: NSLiteralSearch
				     range: range];
      if (range.length == 0)
	return NSNotFound;
      location = range.location;
      range = NSMakeRange(location, length - location);
      range = [str rangeOfCharacterFromSet: wordCSet()
				   options: NSLiteralSearch
				     range: range];
      if (range.length == 0)
	return NSNotFound;
      return range.location;
    }
  else if (location > 0)
    {
      NSString	*str = [self string];
      NSRange	range;

      range = NSMakeRange(0, location);
      range = [str rangeOfCharacterFromSet: wordBreakCSet()
				   options: NSBackwardsSearch|NSLiteralSearch
				     range: range];
      location = range.location;
      range = NSMakeRange(0, location);
      range = [str rangeOfCharacterFromSet: wordCSet()
				   options: NSLiteralSearch
				     range: range];
      if (range.length == 0)
	return NSNotFound;
      return range.location;
    }
  else
    {
      return NSNotFound;
    }
}

/*
 * This is where the fun begins with RTF/RTFD/HTML
 * This is currently ALL FIXME. :-)
 * With love from Michael, hehe.
 */


- (id) initWithRTFD: (NSData*)data
 documentAttributes: (NSDictionary**)dict
{
  return self;
}

- (id) initWithPath: (NSString*)path
 documentAttributes: (NSDictionary**)dict
{
  return self;
}

- (id) initWithURL: (NSURL*)url 
documentAttributes: (NSDictionary**)dict
{
  return self;
}

- (id) initWithRTFDFileWrapper: (NSFileWrapper*)wrapper
            documentAttributes: (NSDictionary**)dict
{
  return self;
}

- (id) initWithHTML: (NSData*)data
 documentAttributes: (NSDictionary**)dict
{
  return self;
}

- (id) initWithHTML: (NSData*)data
            baseURL: (NSURL*)base
 documentAttributes: (NSDictionary**)dict
{
  return self;
}

- (NSData*) RTFFromRange: (NSRange)range
      documentAttributes: (NSDictionary*)dict
{
  return (NSData *)self;
}

- (NSData*) RTFDFromRange: (NSRange)range
       documentAttributes: (NSDictionary*)dict
{
  return (NSData *)self;
}

- (NSFileWrapper*) RTFDFileWrapperFromRange: (NSRange)range
			 documentAttributes: (NSDictionary*)dict
{
  return (NSFileWrapper *)self;
}
@end

@implementation NSMutableAttributedString (AppKit)
- (void) superscriptRange: (NSRange)range
{
  id value;
  int sValue;

  value = [self attribute: NSSuperscriptAttributeName
		  atIndex: range.location
	   effectiveRange: &range];

  sValue = [value intValue];

  sValue++;

  [self addAttribute: NSSuperscriptAttributeName
	       value: [NSNumber numberWithInt: sValue]
	       range: range];
}

- (void) subscriptRange: (NSRange)range
{
  id value;
  int sValue;

  value = [self attribute: NSSuperscriptAttributeName
		  atIndex: range.location
	   effectiveRange: &range];

  sValue = [value intValue];

  sValue--;

  [self addAttribute: NSSuperscriptAttributeName
	       value: [NSNumber numberWithInt: sValue]
	       range: range];
}

- (void) unscriptRange: (NSRange)range
{
  [self addAttribute: NSSuperscriptAttributeName
	       value: [NSNumber numberWithInt: 0]
	       range: range];
}

- (void) applyFontTraits: (NSFontTraitMask)traitMask range: (NSRange)range
{
/* We don't use font traits yet, oops. */
/*
  id value;

  value = [self attribute: NSFontAttributeName
		  atIndex: range.location
	   effectiveRange: range];

  [value setFontTraits: traitMask];

  [self addAttribute: NSFontAttributeName value: value range: range];
*/
}

- (void) setAlignment: (NSTextAlignment)alignment range: (NSRange)range
{
  id value;

  value = [self attribute: NSParagraphStyleAttributeName
		  atIndex: range.location
	   effectiveRange: &range];

  [value setAlignment: alignment];

  [self addAttribute: NSParagraphStyleAttributeName value: value range: range];
}

- (void) fixAttributesInRange: (NSRange)range
{
  [self fixFontAttributeInRange: range];
//  [self fixParagraphStyleAttributeInRange: range];
//  [self fixAttachmentAttributeInRange: range];
}

- (void) fixFontAttributeInRange: (NSRange)range
{
}

- (void) fixParagraphStyleAttributeInRange: (NSRange)range
{
  NSString	*str = [self string];
  unsigned	length = [str length];
  unsigned	location;
  NSRange	r;

  if (range.location > 0)
    {
      /*
       * Extend range backward to take in entire paragraph if necessary.
       */
      r = NSMakeRange(0, range.location);
      r = [str rangeOfCharacterFromSet: paraBreakCSet()
			       options: NSBackwardsSearch|NSLiteralSearch
				 range: r];
      if (r.length == 0)
	{
	  /*
	   * No paragraph before this in range - so extend range right
	   * back to the start of the string.
	   */
	  range.length += range.location;
	  range.location = 0;
	}
      else if (r.location + 1 < range.location)
	{
	  range.length += (range.location - r.location - 1);
	  range.location = r.location + 1;
	}
    }

  /*
   * Extend range forwards to take in entire paragraph if necessary.
   */
  location = r.location + r.length;
  if (location > 0)
    location--;
  r = NSMakeRange(location, length - location);
  r = [str rangeOfCharacterFromSet: paraBreakCSet()
			   options: NSLiteralSearch
			     range: r];
  if (r.length > 0 && r.location > location)
    range.length += (r.location - location);

  /*
   * Now try to step through the range fixing up the paragraph styles in
   * each paragraph so the entire paragraph has the same style as the
   * first character in the paragraph.
   */
  while (range.length > 0)
    {
      NSParagraphStyle	*style;
      NSRange		found;
      unsigned		end;

      /*
       * Determine position of next paragraph end.
       */
      r = [str rangeOfCharacterFromSet: paraBreakCSet()
			       options: NSLiteralSearch
				 range: range];
      if (r.length == 0)
        end = NSMaxRange(range);
      else
	end = r.location + 1;

      /*
       * get the style in effect at the paragraph start.
       */
      style = [self attribute: NSParagraphStyleAttributeName
		      atIndex: location
	       effectiveRange: &found];
      /*
       * Fix up this paragraph to have the starting style.
       */
      while (NSMaxRange(found) < end)
	{
	  NSParagraphStyle	*nextStyle;
	  NSRange		nextFound;

	  nextStyle = [self attribute: NSParagraphStyleAttributeName
			      atIndex: NSMaxRange(found)
		       effectiveRange: &nextFound];
	  if (nextStyle == style || [nextStyle isEqual: style] == YES)
	    {
	      found = nextFound;
	    }
	  else
	    {
	      /*
	       * Styles differ - add the old style to the remainder of the
	       * range.
	       */
	      found.location = NSMaxRange(found);
	      found.length = end - found.location;
	      [self addAttribute: NSParagraphStyleAttributeName
			   value: style
			   range: found];
	    }
	}
      /*
       * Adjust the range to start at the beginning of the next paragraph.
       */
      range.length = NSMaxRange(range) - end;
      range.location = end;
    }
}

- (void) fixAttachmentAttributeInRange: (NSRange)range
{
  unsigned	location = range.location;
  unsigned	end = NSMaxRange(range);

  while (location < end)
    {
      NSDictionary	*attr;

      attr = [self attributesAtIndex: location effectiveRange: &range];
      if ([attr objectForKey: NSAttachmentAttributeName] != nil)
	{
	  unichar	buf[range.length];
	  unsigned	pos = 0;

	  [[self string] getCharacters: buf range: range];
	  while (pos < range.length)
	    {
	      unsigned	start;
	      unsigned	end;

	      while (pos < range.length && buf[pos] == NSAttachmentCharacter)
		pos++;
	      start = pos;
	      while (pos < range.length && buf[pos] == NSAttachmentCharacter)
		pos++;
	      end = pos;
	      if (start != end)
		[self removeAttribute: NSAttachmentAttributeName
				range: NSMakeRange(start, end - start)];
	    }
	}
      location = NSMaxRange(range);
    }
}
@end




/* AttributedStringRTFDAdditions.m created by daniel on Wed 24-Nov-1999 */

@interface NSString (Replacing)
- (NSString*) stringByReplacingEveryOccurrenceOfString: (NSString*)aString
					    withString: (NSString*)other;
@end

@implementation NSString (Replacing)

- (NSString*) stringByReplacingEveryOccurrenceOfString: (NSString*)aString
					    withString: (NSString*)other
{
  unsigned		len = [self length];
  NSMutableString	*erg = [NSMutableString string];
  NSRange		currRange = [self rangeOfString: aString];
  unsigned		prevLocation = 0;

  while (currRange.length > 0)
    {
      if (currRange.location > 0)
	{
	  NSRange	r;

	  r = NSMakeRange(prevLocation, currRange.location - prevLocation);
	  [erg appendString: [self substringWithRange: r]];
	}
      [erg appendString: other];
      currRange.location += currRange.length;
      currRange.length = len - currRange.location;
      prevLocation = currRange.location;
      currRange = [self rangeOfString: aString
			      options: NSLiteralSearch
				range: currRange];
    }
  if (prevLocation < len)
    {
      NSRange	r;

      r = NSMakeRange(prevLocation, len - prevLocation);
      [erg appendString: [self substringWithRange: r]];
    }

  return erg;
}
@end

@implementation NSAttributedString(AttributedStringRTFDAdditions)

- (NSString*) RTFHeaderStringWithContext: (NSMutableDictionary*) contextDict
{
  NSMutableString	*result;
  NSMutableDictionary	*fontDict;

  result = (id)[NSMutableString stringWithString: @"{\\rtf0\\ansi"];
  fontDict = [contextDict objectForKey: @"Fonts"];

  // write Font Table
  if (fontDict != nil)
    {
      NSMutableString	*fontlistString = [NSMutableString string];
      NSString		*table;
      NSEnumerator	*fontEnum;
      id		currFont;
      NSArray		*keyArray;

      keyArray = [fontDict allKeys];
      keyArray = [keyArray sortedArrayUsingSelector: @selector(compare:)];

      fontEnum = [keyArray objectEnumerator];
      while ((currFont = [fontEnum nextObject]) != nil)
	{
	  NSString	*fontFamily;
	  NSString	*detail;

	  fontFamily = [[NSFont fontWithName: currFont size: 12] familyName];

	  detail = [NSString stringWithFormat: @"%@\\f%@ %@;",
	    [fontDict objectForKey: currFont], fontFamily, currFont];
	  [fontlistString appendString: detail];
	}
      table = [NSString stringWithFormat: @"{\\fonttbl%@}\n", fontlistString];
      [result appendString: table];
    }
  return result;
}

- (NSString*) RTFTrailerStringWithContext: (NSMutableDictionary*) contextDict
{
  return @"}";
}

- (NSString*) RTFBodyStringWithContext: (NSMutableDictionary*) contextDict
{
  NSRange		completeRange;
  NSRange		currRange;
  NSString		*string = [self string];
  NSMutableString	*result = [NSMutableString string];
  NSFont		*currentFont = nil;

  completeRange = NSRangeFromString([contextDict objectForKey: @"Range"]);
  currRange = NSMakeRange(completeRange.location, 0);

  while (NSMaxRange(currRange) < NSMaxRange(completeRange))  // save all "runs"
    {
      NSDictionary	*attributes;
      NSString		*substring;
      BOOL		useBraces = NO;
      NSMutableString	*headerString;
      NSMutableString	*trailerString;
      NSEnumerator	*attribEnum;
      id		currAttrib;

      attributes = [self attributesAtIndex: NSMaxRange(currRange)
		     longestEffectiveRange: &currRange
				   inRange: completeRange];
      substring = [string substringWithRange: currRange];
      headerString = (id)[NSMutableString string];
      trailerString = (id)[NSMutableString string];

      /*
       * analyze attributes of current run
       */
      attribEnum = [attributes keyEnumerator];
      while ((currAttrib = [attribEnum nextObject]) != nil)
	{
	  /*
	   * handle fonts
	   */
	  if ([currAttrib isEqualToString: NSFontAttributeName])
	    {
	      NSFont			*font;
	      NSMutableDictionary	*peekDict;
	      NSString			*fontToken;
	      NSString			*fontName;
	      NSFontTraitMask		traits;

	      font = [attributes objectForKey: NSFontAttributeName];
	      peekDict = [contextDict objectForKey: @"Fonts"];
	      fontName = [font familyName];
	      traits = [[NSFontManager sharedFontManager] traitsOfFont: font];

	      /*
	       * maintain a dictionary for the used fonts
	       * (for rtf-header generation)
	       */
	      if (peekDict == nil)
		{
		  peekDict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
		    @"\\f0", fontName, nil];
		  [contextDict setObject: peekDict forKey: @"Fonts"];
		}
	      else
		{
		  if ([peekDict objectForKey: fontName] == nil)
		    {
		      unsigned	count = [peekDict count];
		      NSString	*fCount;

		      fCount = [NSString stringWithFormat: @"\\f%d", count];
		      [peekDict setObject: fCount forKey: fontName];
		    }
		}
	      fontToken = [peekDict objectForKey: fontName];
	      /*
	       * font name
	       */
	      if (![fontName isEqualToString: [currentFont familyName]]
		|| currentFont == nil)
		{
		  [headerString appendString: fontToken];
		}
	      /*
	       * font size
	       */
	      if ([font pointSize] != [currentFont pointSize])
		{
		  int		points = (int)[font pointSize]*2;
		  NSString	*pString;

		  pString = [NSString stringWithFormat: @"\\fs%d", points];
		  [headerString appendString: pString];
		}
	      /*
	       * font attributes
	       */
	      if (traits & NSItalicFontMask)
		{
		  [headerString appendString: @"\n\\i "];
		}
	      if (traits & NSBoldFontMask)
		{
		  [headerString appendString: @"\n\\b "];
		  [trailerString appendString: @"\n\\b0"];
		}
	      currentFont = font;
	    }
	  else if ([currAttrib isEqualToString: NSParagraphStyleAttributeName])
	    {
	    }
	  else if ([currAttrib isEqualToString: NSForegroundColorAttributeName])
	    {
	    }
	  else if ([currAttrib isEqualToString: NSUnderlineStyleAttributeName])
	    {
	    }
	  else if ([currAttrib isEqualToString: NSSuperscriptAttributeName])
	    {
	    }
	  else if ([currAttrib isEqualToString: NSBackgroundColorAttributeName])
	    {
	    }
	  else if ([currAttrib isEqualToString: NSAttachmentAttributeName])
	    {
	    }
	  else if ([currAttrib isEqualToString: NSLigatureAttributeName])
	    {
	    }
	  else if ([currAttrib isEqualToString: NSBaselineOffsetAttributeName])
	    {
	    }
	  else if ([currAttrib isEqualToString: NSKernAttributeName])
	    {
	    }
	}
    // write down current run
      substring = [substring stringByReplacingString: @"\\"
					  withString: @"\\\\"];
      substring = [substring stringByReplacingString: @"\n"
					  withString: @"\\\n"];
      substring = [substring stringByReplacingString: @"{"
					  withString: @"\\{"];
      substring = [substring stringByReplacingString: @"}"
					  withString: @"\\}"];
      if (useBraces)
	{
	  NSString	*braces;

	  braces = [NSString stringWithFormat: @"{%@%@%@}",
	    headerString, substring, trailerString];
	  [result appendString: braces];
	}
      else
	{
	  NSString	*nobraces;

	  nobraces = [NSString stringWithFormat: @"%@%@%@",
	    headerString, substring, trailerString];
	  [result appendString: nobraces];
	}
    }
  return result;
}


- (NSString*) RTFDStringFromRange: (NSRange)range
	       documentAttributes: (NSDictionary*)dict
{
  NSMutableString	*output = [NSMutableString string];
  NSString		*headerString;
  NSString		*trailerString;
  NSString		*bodyString;
  NSMutableDictionary	*context = [NSMutableDictionary dictionary];

  [context setObject: (dict ? dict : [NSMutableDictionary dictionary])
	      forKey: @"DocumentAttributes"];
  [context setObject: NSStringFromRange(range) forKey: @"Range"];

  /*
   * do not change order! (esp. body has to be generated first; builds context)
   */
  bodyString = [self RTFBodyStringWithContext: context];
  trailerString = [self RTFTrailerStringWithContext: context];
  headerString = [self RTFHeaderStringWithContext: context];

  [output appendString: headerString];
  [output appendString: bodyString];
  [output appendString: trailerString];
  return (NSString*)output;
}

- (NSData*) RTFDFromRange: (NSRange)range
       documentAttributes: (NSDictionary*)dict
{
  return [[self RTFDStringFromRange: range documentAttributes: dict]
    dataUsingEncoding: NSNEXTSTEPStringEncoding];
}
@end
