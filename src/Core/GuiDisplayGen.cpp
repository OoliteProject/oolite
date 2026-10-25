/*

GuiDisplayGen.m

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#include "GuiDisplayGen.h"
#include "Universe.h"
#include "GameController.h"
#include "PlayerEntity.h"
#include "PlayerEntityControls.h"
#include "OOTextureSprite.h"
#include "ResourceManager.h"
#include "OOSound.h"
#include "OOStringExpander.h"
#include "OOStringParsing.h"
#include "HeadUpDisplay.h"
#include "OOTexture.h"
#include "OOJavaScriptEngine.h"
#include "PlayerEntityStickProfile.h"
#include "OOSystemDescriptionManager.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/objc/OOAssert.h"

#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"
#include <map>
#include "OOObjCPList.h"

OOINLINE BOOL RowInRange(OOGUIRow row, NSRange range)
{
	return ((int)range.location <= row && row < (int)(range.location + range.length));
}


namespace {

// words[from...] joined by single spaces (as the old array join with @" " did).
std::string WordsJoinedBySpace(const std::vector<std::string> &words, std::size_t from)
{
	std::string result;
	for (std::size_t i = from; i < words.size(); i++)
	{
		if (i != from)  result += " ";
		result += words[i];
	}
	return result;
}

// -setTitle:'s rule: an empty title is no title.
std::optional<std::string> TitleFrom(const std::optional<std::string> &title)
{
	if (title.has_value() && title->empty())  return std::nullopt;
	return title;
}


// A row key that makes a row unselectable (GUI_KEY_SKIP).
bool IsSkipKey(const std::string &key)
{
	return key == "SKIP-ROW";
}


// The characters -drawGLDisplay does not highlight at either end of a column (' ' and the narrow
// space '\037'), trimmed as -stringByTrimmingCharactersInSet: did: both are ASCII, so bytes.
std::string TrimmedForHighlight(const std::string &text)
{
	const char *const kTrimmed = " \037";
	const std::size_t first = text.find_first_not_of(kTrimmed);
	if (first == std::string::npos)  return std::string();
	const std::size_t last = text.find_last_not_of(kTrimmed);
	return text.substr(first, last - first + 1);
}

}	// namespace

namespace {

// The descriptor's "name" as -oo_stringForKey: read it (a string, or a number's -stringValue), or
// nullopt (nil).
std::optional<std::string> DescriptorName(const oo::PList &descriptor)
{
	const oo::PList *name = descriptor.find("name");
	if (name == nullptr || !(name->isString() || name->isNumber()))  return std::nullopt;
	return descriptor.get<std::string>("name");
}


oo::Ref<OOTexture> TextureForGUITexture(const oo::PList &descriptor, uint32_t srgbaOption)
{
	/*
		GUI textures like backgrounds, foregrounds etc. are not processed in any way after loading. However, they are
		subject to tone nmapping and gamma correction at the end of the render pass. So we need to declare them as
		SRGBA textures here so that OpenGL will automatically convert them to linear space upon loading and the
		subsequent tone mapping and gamma correction shader operations will not result in heavy distortion of their
		colors.

		Also, remember that if no shaders are in use (as in lower detail levels), then we don't need to declare anything.
	*/
	if (!GuiDisplayGenUniverseUseShaders())  srgbaOption = 0;
	return OOTexture::textureWithName(DescriptorName(descriptor),
										   "Images",
										   kOOTextureDefaultOptions | kOOTextureNoShrink | srgbaOption,
										   kOOTextureDefaultAnisotropy,
										   kOOTextureDefaultLODBias);
}


/*
	Load a texture sprite given a descriptor. Null where there is no such texture.
*/
oo::Ref<OOTextureSprite> NewTextureSpriteWithDescriptor(const oo::PList &descriptor, uint32_t srgbaOption)
{
	oo::Ref<OOTexture>	texture;
	NSSize			size;

	texture = TextureForGUITexture(descriptor, srgbaOption);
	if (texture.get() == nil)  return nullptr;

	double specifiedWidth = descriptor.get<double>("width", -INFINITY);
	double specifiedHeight = descriptor.get<double>("height", -INFINITY);
	bool haveWidth = isfinite(specifiedWidth);
	bool haveHeight = isfinite(specifiedHeight);

	if (haveWidth && haveHeight)
	{
		// Both specified, use directly without calling -originalDimensions (which may block).
		size.width = specifiedWidth;
		size.height = specifiedHeight;
	}
	else
	{
		NSSize originalDimensions = texture->originalDimensions();

		if (haveWidth)
		{
			// Width specified, but not height; preserve aspect ratio.
			CGFloat ratio = originalDimensions.height / originalDimensions.width;
			size.width = specifiedWidth;
			size.height = ratio * size.width;
		}
		else if (haveHeight)
		{
			// Height specified, but not width; preserve aspect ratio.
			CGFloat ratio = originalDimensions.width / originalDimensions.height;
			size.height = specifiedHeight;
			size.width = ratio * size.height;
		}
		else
		{
			// Neither specified; use backwards-compatible behaviour.
			size = originalDimensions;
		}
	}

	return OOTextureSprite::initWithTexture(texture.get(), size);
}

}	// namespace


static BOOL _refreshStarChart = NO;	// set by refreshStarChart(), read by drawStarChart()


GuiDisplayGen::GuiDisplayGen()
{
	size_in_pixels  = NSMakeSize(MAIN_GUI_PIXEL_WIDTH, MAIN_GUI_PIXEL_HEIGHT);
	n_columns		= GUI_DEFAULT_COLUMNS;
	n_rows			= GUI_DEFAULT_ROWS;
	pixel_row_center = size_in_pixels.width / 2;
	pixel_row_height = MAIN_GUI_ROW_HEIGHT;
	pixel_row_start	= MAIN_GUI_PIXEL_ROW_START;		// first position down the page...
	max_alpha = 1.0;

	pixel_text_size = NSMakeSize(0.9f * pixel_row_height, pixel_row_height);	// main gui has 18x20 characters

	pixel_title_size = NSMakeSize(pixel_row_height * 1.75f, pixel_row_height * 1.5f);

	int stops[6] = {0, 192, 256, 320, 384, 448};
	unsigned i;

	rowRange = NSMakeRange(0,n_rows);

	rowText.reserve(n_rows);
	rowKey.reserve(n_rows);
	rowColor.reserve(n_rows);

	for (i = 0; i < n_rows; i++)
	{
		rowText.push_back(oo::PList("."));
		rowKey.push_back(oo::str::format("%d", (int)i));
		rowColor.push_back(oo::Ref<OOColor>(OOColor::yellowColor()));
		rowPosition[i].x = 0.0f;
		rowPosition[i].y = size_in_pixels.height - (pixel_row_start + i * pixel_row_height);
		rowAlignment[i] = GUI_ALIGN_LEFT;
	}

	for (i = 0; i < n_columns; i++)
	{
		tabStops[i] = stops[i];
	}

	title = std::string();	// an empty title, not none (-setTitle: would have made it none)
	textColor = oo::Ref<OOColor>(OOColor::yellowColor());

	drawPosition = make_vector(0.0f, 0.0f, 640.0f);

	backgroundSpecial = GUI_BACKGROUND_SPECIAL_NONE;

	guiUserSettings = ResourceManager::dictionaryFromFilesNamed("gui-settings.plist", "Config", YES);
}


GuiDisplayGen::GuiDisplayGen(NSSize gui_size,
								  int gui_cols,
								  int gui_rows,
								  int gui_row_height,
								  int gui_row_start,
								  const std::optional<std::string> &gui_title)
{
	size_in_pixels  = gui_size;
	n_columns		= gui_cols;
	n_rows			= gui_rows;
	pixel_row_center = size_in_pixels.width / 2;
	pixel_row_height = gui_row_height;
	pixel_row_start	= gui_row_start;		// first position down the page...
	max_alpha = 1.0;

	pixel_text_size = NSMakeSize(pixel_row_height, pixel_row_height);

	pixel_title_size = NSMakeSize(pixel_row_height * 1.75f, pixel_row_height * 1.5f);

	unsigned i;

	rowRange = NSMakeRange(0,n_rows);

	rowText.reserve(n_rows);
	rowKey.reserve(n_rows);
	rowColor.reserve(n_rows);

	for (i = 0; i < n_rows; i++)
	{
		rowText.push_back(oo::PList(""));
		rowKey.push_back(std::string());
		rowColor.push_back(oo::Ref<OOColor>(OOColor::greenColor()));
		rowPosition[i].x = 0.0f;
		rowPosition[i].y = size_in_pixels.height - (pixel_row_start + i * pixel_row_height);
		rowAlignment[i] = GUI_ALIGN_LEFT;
	}

	title = gui_title;	// as given (not through -setTitle:)
	textColor = oo::Ref<OOColor>(OOColor::yellowColor());
}


GuiDisplayGen::~GuiDisplayGen() = default;


void GuiDisplayGen::resizeWithPixelSize(NSSize gui_size,
											 int gui_cols,
											 int gui_rows,
											 int gui_row_height,
											 int gui_row_start,
											 const std::optional<std::string> &gui_title)
{
	clear();
	//
	size_in_pixels  = gui_size;
	n_columns		= gui_cols;
	n_rows			= gui_rows;
	pixel_row_center = size_in_pixels.width / 2;
	pixel_row_height = gui_row_height;
	pixel_row_start	= gui_row_start;		// first position down the page...

	pixel_text_size = NSMakeSize(pixel_row_height, pixel_row_height);
	pixel_title_size = NSMakeSize(pixel_row_height * 1.75f, pixel_row_height * 1.5f);

	rowRange = NSMakeRange(0,n_rows);
	clear();
	//
	title = TitleFrom(gui_title);
}


void GuiDisplayGen::resizeTo(NSSize gui_size,
								  int csize,
								  const std::optional<std::string> &gui_title)
{
	clear();
	//
	size_in_pixels  = gui_size;
	n_columns		= gui_size.width / csize;
	n_rows			= (int)gui_size.height / csize;

	title = TitleFrom(gui_title);

	pixel_row_center = gui_size.width / 2;
	pixel_row_height = csize;
	currentRow = n_rows - 1;		// first position down the page...

	if (title.has_value())
		pixel_row_start = 2.75f * csize + 0.5f * (gui_size.height - n_rows * csize);
	else
		pixel_row_start = csize + 0.5f * (gui_size.height - n_rows * csize);

	rowText.clear();
	rowKey.clear();
	rowColor.clear();

	unsigned i;
	for (i = 0; i < n_rows; i++)
	{
		rowText.push_back(oo::PList(""));
		rowKey.push_back(std::string());
		rowColor.push_back(oo::Ref<OOColor>(OOColor::greenColor()));
		rowPosition[i].x = 0.0f;
		rowPosition[i].y = size_in_pixels.height - (pixel_row_start + i * pixel_row_height);
		rowAlignment[i] = GUI_ALIGN_LEFT;
	}

	pixel_text_size = NSMakeSize(csize, csize);
	pixel_title_size = NSMakeSize(csize * 1.75f, csize * 1.5f);

	OO_LOG("gui.reset", "gui {} reset to rows:{} columns:{} start:{}", oo::str::format("<GuiDisplayGen %s>", oo::str::pointerDescription(this).c_str()), n_rows, n_columns, pixel_row_start);

	rowRange = NSMakeRange(0,n_rows);
	clear();
}


NSSize GuiDisplayGen::size()
{
	return size_in_pixels;
}


unsigned GuiDisplayGen::columns()
{
	return n_columns;
}


unsigned GuiDisplayGen::rows()
{
	return n_rows;
}


unsigned GuiDisplayGen::rowHeight()
{
	return pixel_row_height;
}


int GuiDisplayGen::rowStart()
{
	return pixel_row_start;
}


std::optional<std::string> GuiDisplayGen::getTitle()
{
	return title;
}


void GuiDisplayGen::setTitle(const std::optional<std::string> &str)
{
	title = TitleFrom(str);
}


void GuiDisplayGen::setDrawPosition(Vector vector)
{
	drawPosition = vector;
}


Vector GuiDisplayGen::getDrawPosition()
{
	return drawPosition;
}


oo::PList GuiDisplayGen::userSettings()
{
	return guiUserSettings;
}


void GuiDisplayGen::fadeOutFromTime(OOTimeAbsolute /*now_time*/, OOTimeDelta duration)
{
	if (fade_alpha <= 0.0f)
	{
		return;
	}
	if (duration == 0.0)
		fade_sign = -1000.0f;
	else
		fade_sign = (float)(-fade_alpha / duration);
}


void GuiDisplayGen::stopFadeOuts()
{
	fade_sign = 0.0f;
}


GLfloat GuiDisplayGen::alpha()
{
	return fade_alpha;
}


void GuiDisplayGen::setAlpha(GLfloat an_alpha)
{
	fade_alpha = an_alpha * max_alpha;
}


void GuiDisplayGen::setMaxAlpha(GLfloat an_alpha)
{
	max_alpha = an_alpha;
}


void GuiDisplayGen::setBackgroundColor(::OOColor *color)
{
	backgroundColor = oo::Ref<OOColor>(color);
}


::OOColor *GuiDisplayGen::getTextColor()
{
	return textColor.get();
}


// default text colour for rows
void GuiDisplayGen::setTextColor(::OOColor *color)
{
	if (color == nullptr)  textColor = OOColor::yellowColor();
	else  textColor = oo::Ref<OOColor>(color);
}


::OOColor *GuiDisplayGen::getTextCommsColor()
{
	return textCommsColor.get();
}


void GuiDisplayGen::setTextCommsColor(::OOColor *color)
{
	if (color == nullptr)  textCommsColor = OOColor::yellowColor();
	else  textCommsColor = oo::Ref<OOColor>(color);
}


oo::Ref<OOColor> GuiDisplayGen::colorFromSetting(const std::optional<std::string> &setting, ::OOColor *def)
{

	oo::Ref<OOColor> col;
	if (setting.has_value()) {
		const oo::PList *description = guiUserSettings.find(*setting);
		col = OOColor::colorWithDescription((description != nullptr) ? *description : oo::PList());
	}
	if (col == nullptr) {
		if (def != nullptr) {
			col = oo::Ref<OOColor>(def);
			// def = nil => use default_text_color
		} else {
			col = textColor;
		}
	}
	return col;	// -copy of an immutable colour was the colour itself
}


void GuiDisplayGen::setGLColorFromSetting(const std::optional<std::string> &setting, ::OOColor *def, GLfloat alpha)
{
	GLfloat r,g,b,a;
	oo::Ref<OOColor>	col = colorFromSetting(setting, def);
	col->getRed(&r, &g, &b, &a);

	OOGL(glColor4f(r, g, b, a*alpha));
}


void GuiDisplayGen::setGuiColorSettingFromKey(const std::string &key, ::OOColor *col)
{
	// With no settings (nil), the mutable copy was nil too and nothing changed.
	oo::PList::Dict *settings = guiUserSettings.getIf<oo::PList::Dict>();
	if (settings == nullptr)  return;
	if (col == nullptr)
	{
		settings->erase(key);
	}
	else
	{
		(*settings)[key] = OOColorObjectNode(col);
	}
}


void GuiDisplayGen::setCharacterSize(NSSize character_size)
{
	pixel_text_size = character_size;
}


void GuiDisplayGen::setShowAdvancedNavArray(bool inFlag)
{
	showAdvancedNavArray = inFlag;
}


void GuiDisplayGen::setColor(::OOColor *color, OOGUIRow row)
{
	if (RowInRange(row, rowRange))
		rowColor[row] = oo::Ref<OOColor>(color);
}


oo::PList GuiDisplayGen::objectForRow(OOGUIRow row)
{
	if (RowInRange(row, rowRange))
		return rowText[row];	// a string, or an array of column strings
	else
		return oo::PList();	// null, where this was nil
}


OOGUIRow GuiDisplayGen::rowForKey(const std::optional<std::string> &key)
{
	if (!key.has_value())  return -1;	// a nil key matched nothing
	for (unsigned i=0;i<rowKey.size();i++)
	{
		if (*key == rowKey[i])
		{
			return (OOGUIRow)i;
		}
	}
	return -1;
}


std::optional<std::string> GuiDisplayGen::keyForRow(OOGUIRow row)
{
	if (RowInRange(row, rowRange))
		return rowKey[row];
	else
		return std::nullopt;
}


OOGUIRow GuiDisplayGen::getSelectedRow()
{
	if (RowInRange(selectedRow, selectableRange))
		return selectedRow;
	else
		return -1;
}


bool GuiDisplayGen::setSelectedRow(OOGUIRow row)
{
	if ((row == selectedRow) && RowInRange(row, selectableRange))
	{
		return true;
	}
	if (RowInRange(row, selectableRange))
	{
		if (!IsSkipKey(rowKey[row]))
		{
			selectedRow = row;
			reportSelectedRow(row);
			return true;
		}
	}
	return false;
}


bool GuiDisplayGen::setNextRow(int direction)
{
	OOGUIRow row = selectedRow + direction;
	while (RowInRange(row, selectableRange))
	{
		if (!IsSkipKey(rowKey[row]))
		{
			selectedRow = row;
			reportSelectedRow(row);
			return true;
		}
		row += direction;
	}
	return false;
}


bool GuiDisplayGen::setFirstSelectableRow()
{
	NSUInteger row = selectableRange.location;
	while (RowInRange(row, selectableRange))
	{
		if (!IsSkipKey(rowKey[row]))
		{
			selectedRow = row;
			reportSelectedRow(row);
			return true;
		}
		row++;
	}
	selectedRow = -1;
	return false;
}


bool GuiDisplayGen::setLastSelectableRow()
{
	NSUInteger row = selectableRange.location + selectableRange.length - 1;
	while (RowInRange(row, selectableRange))
	{
		if (!IsSkipKey(rowKey[row]))
		{
			selectedRow = row;
			reportSelectedRow(row);
			return true;
		}
		row--;
	}
	selectedRow = -1;
	return false;
}


void GuiDisplayGen::reportSelectedRow(int row)
{
	// key, row, text - stopping at the first missing one, as +arrayWithObjects: stopped at nil.
	std::vector<oo::PList> arguments;
	const std::optional<std::string> key = keyForRow(row);
	if (key.has_value())
	{
		arguments.emplace_back(*key);
		arguments.emplace_back(row);	// +numberWithInt: (the same JS number)
		const std::optional<std::string> text = selectedRowText();
		if (text.has_value())  arguments.emplace_back(*text);
	}
	if (PLAYER != nullptr)  PLAYER->doScriptEvent(OOJSID("guiSelectedRowChanged"), arguments);
}


void GuiDisplayGen::setNoSelectedRow()
{
	selectedRow = -1;
}


std::optional<std::string> GuiDisplayGen::selectedRowText()
{
	const oo::PList &text = rowText[selectedRow];
	if (const std::string *string = text.getIf<std::string>())
		return *string;
	if (text.isArray())
	{
		const oo::PList *first = text.at(0);	// the first column
		if (first != nullptr && first->isString())  return *first->getIf<std::string>();
	}
	return std::nullopt;
}


std::optional<std::string> GuiDisplayGen::selectedRowKey()
{
	// (the old test let selectedRow == count through, and -objectAtIndex: then raised)
	if ((selectedRow < 0)||((unsigned)selectedRow >= rowKey.size()))
		return std::nullopt;
	else
		return rowKey[selectedRow];
}


void GuiDisplayGen::setShowTextCursor(bool yesno)
{
	showTextCursor = yesno;
}


void GuiDisplayGen::setCurrentRow(OOGUIRow value)
{
	if ((value < 0)||((unsigned)value >= n_rows))
	{
		showTextCursor = false;
		currentRow = -1;
	}
	else
	{
		currentRow = value;
	}
}


NSRange GuiDisplayGen::getSelectableRange()
{
	return selectableRange;
}


void GuiDisplayGen::setSelectableRange(NSRange range)
{
	selectableRange = range;
}


void GuiDisplayGen::setTabStops(OOGUITabSettings stops)
{
	if (stops != NULL)  memmove(tabStops, stops, sizeof tabStops);
}

void GuiDisplayGen::overrideTabs(OOGUITabSettings stops, const std::string &setting, NSUInteger len)
{
	const oo::PList *override = guiUserSettings.get<oo::PList::Array>(setting, nullptr);
	NSUInteger i;
	if (stops != NULL && override != nil)
	{
		if (len > GUI_MAX_COLUMNS)
		{
			len = GUI_MAX_COLUMNS;
		}
		for (i=0;i<len;i++)
		{
			stops[i] = override->at<NSUInteger>(i, stops[i]);
		}
	}
}


void GuiDisplayGen::clear()
{
	clearAndKeepBackground(false);
}


void GuiDisplayGen::clearAndKeepBackground(bool keepBackground)
{
	unsigned i;
	setTitle(std::nullopt);
	for (i = 0; i < n_rows; i++)
	{
		setText("", i, GUI_ALIGN_LEFT);
		setColor(textColor.get(), i);
		//
		setKey(std::string(GUI_KEY_SKIP), i);
		//
		rowFadeTime[i] = 0.0f;
	}
	setShowTextCursor(false);
	setSelectableRange(NSMakeRange(0,0));
	if (!keepBackground) clearBackground();
}


void GuiDisplayGen::setKey(const std::string &str, OOGUIRow row)
{
	if (RowInRange(row, rowRange))
		rowKey[row] = str;
}


void GuiDisplayGen::setText(const std::string &str, OOGUIRow row)
{
	if (RowInRange(row, rowRange))
	{
		rowText[row] = oo::PList(str);
	}
}


void GuiDisplayGen::setText(const std::optional<std::string> &str, OOGUIRow row, OOGUIAlignment alignment)
{
	if (str.has_value() && RowInRange(row, rowRange))
	{
		rowText[row] = oo::PList(*str);
		rowAlignment[row] = alignment;
	}
}


int GuiDisplayGen::rowAtVirtualJoystickPosition(NSPoint vjpos)
{
	// The cursor maths of -drawGUI:drawCursor: (which calls this), y only: the row does not depend
	// on x. Bead oo-3rb.348.
	double cursor_y = -size_in_pixels.height * vjpos.y;
	if (cursor_y < -size_in_pixels.height * 0.5)  cursor_y = -size_in_pixels.height * 0.5f;
	if (cursor_y > size_in_pixels.height * 0.5)   cursor_y = size_in_pixels.height * 0.5f;

	return 1 + (float)floor((0.5f * size_in_pixels.height - pixel_row_start - cursor_y) / pixel_row_height);
}


OOGUIRow GuiDisplayGen::addLongText(const std::optional<std::string> &str,
										 OOGUIRow row,
										 OOGUIAlignment alignment)
{
	// nil: -rangeOfString: answered location 0 and -componentsSeparatedByString: no lines.
	if (!str.has_value())  return row;

	if (str->find('\n') != std::string::npos)
	{
		for (const std::string &line : oo::str::split(*str, "\n"))
		{
			row = addLongText(line, row, alignment);
		}
		return row;
	}

	NSSize chSize = pixel_text_size;
	NSSize strsize = cxx_OORectFromString(*str, 0.0f, 0.0f, chSize).size;
	if (strsize.width < size_in_pixels.width)
	{
		setText(str, row, alignment);
		return row + 1;
	}
	else
	{
		const std::vector<std::string>	words = oo::str::tokens(*str);
		std::size_t						next = 0;	// words moved to string1
		std::string						string1;
		strsize.width = 0.0f;
		while ((strsize.width < size_in_pixels.width)&&(next < words.size()))
		{
			string1 += words[next];
			string1 += " ";
			next++;
			strsize = cxx_OORectFromString(string1, 0.0f, 0.0f, chSize).size;
			if (next < words.size())
				strsize.width += cxx_OORectFromString(words[next], 0.0f, 0.0f, chSize).size.width;
		}
		const std::string string2 = WordsJoinedBySpace(words, next);
		setText(string1, row, alignment);
		return  addLongText(string2, row+1, alignment);
	}
}


std::optional<std::string> GuiDisplayGen::reflowTextForMFD(const std::optional<std::string> &input)
{
	std::string		output;
	NSSize  		chSize = pixel_text_size;
	NSUInteger  	limit = chSize.width * 15;
	// nil split into no lines: the result was an empty string, not nil.
	if (!input.has_value())  return output;
	for (const std::string &line : oo::str::split(*input, "\n"))
	{
		const std::vector<std::string>	words = oo::str::tokens(line);
		std::size_t						first = 0;	// words consumed
		std::string						accum;
		if (!words.empty())
		{
			while (words.size() - first > 1)
			{
				accum += words[first];
				accum += " ";
				if (cxx_OORectFromString(accum, 0.0f, 0.0f,chSize).size.width + cxx_OORectFromString(words[first + 1], 0.0f, 0.0f,chSize).size.width > limit)
				{
					// can't fit next word on this line
					// (-whitespaceCharacterSet trimming: accum holds tokens and spaces, no newlines)
					output += oo::str::trimWhitespaceAndNewlines(accum);
					output += "\n";
					accum.clear();
				}
				first++;
			}
			output += accum;
			output += words[first];
		}
		output += "\n";
	}

	return output;
}


void GuiDisplayGen::leaveLastLine()
{
	unsigned i;
	for (i=0; i < n_rows-1; i++)
	{
		rowText[i] = oo::PList("");
		rowColor[i] = textColor;
		rowKey[i] = std::string();
		rowAlignment[i] = GUI_ALIGN_LEFT;
		rowFadeTime[i]	= 0.0f;
	}
	rowFadeTime[i]	= 0.4f; // fade the last line...
}


oo::PList GuiDisplayGen::getLastLines()	// text, colour, fade time - text, colour, fade time
{
	if (n_rows <1) return oo::PList();

	// we have at least 1 row!

	unsigned				i = n_rows-1;
	OORGBAComponents		col = (rowColor[i] != nullptr) ? rowColor[i]->rgbaComponents() : OORGBAComponents{};	// a nil colour answered zeros
	oo::PList::Array		result;

	/*	Row r's text, colour and fade time, as -arrayWithObjects: took them: the text is what
		-oo_stringAtIndex: read (a string, or a number's -stringValue); anything else was nil, which
		ended the list there. Returns whether it was appended.
	*/
	auto appendRow = [&](unsigned r, const OORGBAComponents &c) -> bool
	{
		const oo::PList &text = rowText[r];
		if (!text.isString() && !text.isNumber())  return false;
		result.emplace_back(oo::PList(oo::PList::Array{ text }).at<std::string>(0));
		result.emplace_back(oo::str::format("%.3g %.3g %.3g %.3g", c.r, c.g, c.b, c.a));
		result.push_back(oo::PList::singleReal(rowFadeTime[r]));	// +numberWithFloat:
		return true;
	};

	if (i>0)
	{
		// we have at least 2 rows!
		OORGBAComponents	col0 = (rowColor[i-1] != nullptr) ? rowColor[i-1]->rgbaComponents() : OORGBAComponents{};
		if (appendRow(i-1, col0))  appendRow(i, col);
	}
	else
	{
		appendRow(i, col);
	}
	return oo::PList(std::move(result));
}


void GuiDisplayGen::printLongText(const std::optional<std::string> &str,
									   OOGUIAlignment alignment,
									   ::OOColor *text_color,
									   float text_fade,
									   const std::optional<std::string> &text_key,
									   std::vector<std::string> *text_array)
{
	// print a multi-line message
	//
	// nil: -rangeOfString: answered location 0 and -componentsSeparatedByString: no lines.
	if (!str.has_value())  return;
	if (str->find('\n') != std::string::npos)
	{
		for (const std::string &line : oo::str::split(*str, "\n"))
			printLongText(line, alignment, text_color, text_fade, text_key, text_array);
		return;
	}

	OOGUIRow row = currentRow;
	if (row == (OOGUIRow)n_rows - 1)
		scrollUp(1);
	NSSize chSize = pixel_text_size;
	NSSize strsize = cxx_OORectFromString(*str, 0.0f, 0.0f, chSize).size;
	if (strsize.width < size_in_pixels.width)
	{
		setText(str, row, alignment);
		if (text_color)
			setColor(text_color, row);
		if (text_key.has_value())
			setKey(*text_key, row);
		rowFadeTime[row] = text_fade;
		if (currentRow < (OOGUIRow)n_rows - 1)
			currentRow++;
		if (text_array)
			text_array->push_back(*str);
	}
	else
	{
		const std::vector<std::string>	words = oo::str::tokens(*str);
		std::size_t						next = 0;	// words moved to string1
		std::string						string1;
		strsize.width = 0.0f;
		while ((strsize.width < size_in_pixels.width)&&(next < words.size()))
		{
			string1 += words[next];
			string1 += " ";
			next++;
			strsize = cxx_OORectFromString(string1, 0.0f, 0.0f, chSize).size;
			if (next < words.size())
				strsize.width += cxx_OORectFromString(words[next], 0.0f, 0.0f, chSize).size.width;
		}

		setText(string1, row, alignment);

		const std::string string2 = WordsJoinedBySpace(words, next);
		if (text_color)
			setColor(text_color, row);
		if (text_key.has_value())
			setKey(*text_key, row);
		if (text_array)
			text_array->push_back(string1);
		rowFadeTime[row] = text_fade;
		printLongText(string2, alignment, text_color, text_fade, text_key, text_array);
	}
}


void GuiDisplayGen::printLineNoScroll(const std::optional<std::string> &str,
										   OOGUIAlignment alignment,
										   ::OOColor *text_color,
										   float text_fade,
										   const std::optional<std::string> &text_key,
										   std::vector<std::string> *text_array)
{
	setText(str, currentRow, alignment);
	if (text_color)
		setColor(text_color, currentRow);
	if (text_key.has_value())
		setKey(*text_key, currentRow);
	if (text_array && str.has_value())	// adding nil raised
		text_array->push_back(*str);
	rowFadeTime[currentRow] = text_fade;
}


void GuiDisplayGen::setArray(const std::vector<std::string> &arr, OOGUIRow row)
{
	if (RowInRange(row, rowRange))
	{
		oo::PList::Array columns;
		for (const std::string &column : arr)  columns.push_back(oo::PList(column));
		rowText[row] = oo::PList(std::move(columns));
	}
}


void GuiDisplayGen::insertItemsFromArray(const oo::PList &items,
											  const oo::PList &item_keys,
											  OOGUIRow row,
											  ::OOColor *text_color)
{
	if (items.isNull())
		return;
	if(items.count() == 0)
		return;

	NSUInteger n_items = items.count();
	if ((!item_keys.isNull())&&(item_keys.count() != n_items))
	{
		// throw exception
		OORaiseException("ArrayLengthMismatchException",
						 "The array sent as 'item_keys' to insertItemsFromArray::: must contain the same number of objects as the array 'items'");
	}

	unsigned i;
	for (i = n_rows; i >= row + n_items ; i--)
	{
		setKey(keyForRow(i - n_items).value_or(""), i);
		// the row's text or columns moved down (-objectForRow: gave nil out of range)
		const oo::PList old_row_info = RowInRange(i - n_items, rowRange) ? rowText[i - n_items] : oo::PList();
		if (old_row_info.isArray() && RowInRange(i, rowRange))
			rowText[i] = old_row_info;
		if (const std::string *text = old_row_info.getIf<std::string>())
			setText(*text, i);
	}
	for (i = 0; i < n_items; i++)
	{
		const oo::PList &new_row_info = *items.at(i);
		if (text_color)
			setColor(text_color, row + i);
		else
			setColor(textColor.get(), row + i);
		if (const oo::PList::Array *columns = new_row_info.getIf<oo::PList::Array>())
		{
			std::vector<std::string> columnTexts;
			for (const oo::PList &column : *columns)
			{
				if (const std::string *text = column.getIf<std::string>())  columnTexts.push_back(*text);
			}
			setArray(columnTexts, row + i);
		}
		if (const std::string *text = new_row_info.getIf<std::string>())
			setText(*text, row + i);
		if (!item_keys.isNull())
			setKey(item_keys.at<std::string>(i), row + i);
		else
			setKey("", row + i);
	}
}


void GuiDisplayGen::scrollUp(int how_much)
{
	unsigned i;
	for (i = 0; i + how_much < n_rows; i++)
	{
		rowText[i] = rowText[i + how_much];
		rowColor[i] = rowColor[i + how_much];
		rowKey[i] = rowKey[i + how_much];
		rowAlignment[i] = rowAlignment[i + how_much];
		rowFadeTime[i]	= rowFadeTime[i + how_much];
	}
	for (; i < n_rows; i++)
	{
		rowText[i] = oo::PList("");
		rowColor[i] = textColor;
		rowKey[i] = std::string();
		rowAlignment[i] = GUI_ALIGN_LEFT;
		rowFadeTime[i]	= 0.0f;
	}
}


void GuiDisplayGen::clearBackground()
{
	setBackgroundTextureDescriptor(oo::PList());
	setForegroundTextureDescriptor(oo::PList());
}


void GuiDisplayGen::setBackgroundTextureSpecial(OOGUIBackgroundSpecial spec, bool withBackground)
{
	if (withBackground)
	{
		oo::PList bgDescriptor;
		OOGalaxyID galaxy_number = (PLAYER != nullptr ? PLAYER->galaxyNumber() : OOGalaxyID{});

		switch (spec)
		{
		case GUI_BACKGROUND_SPECIAL_CUSTOM:
		case GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_SHORTEST:
		case GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_QUICKEST:
			bgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("custom_chart_mission") : oo::PList());
			if (bgDescriptor.isNull())
			{
				bgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("short_range_chart_mission") : oo::PList());
				if (bgDescriptor.isNull())
				{
					bgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("short_range_chart") : oo::PList());
				}
			}
			break;
		case GUI_BACKGROUND_SPECIAL_SHORT:
		case GUI_BACKGROUND_SPECIAL_SHORT_ANA_SHORTEST:
		case GUI_BACKGROUND_SPECIAL_SHORT_ANA_QUICKEST:
			bgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("short_range_chart_mission") : oo::PList());
			if (bgDescriptor.isNull())
			{
				bgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("short_range_chart") : oo::PList());
			}
			break;
		case GUI_BACKGROUND_SPECIAL_LONG:
		case GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST:
		case GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST:
			bgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey(oo::str::format("long_range_chart%d_mission", galaxy_number+1)) : oo::PList());
			if (bgDescriptor.isNull())
			{
				bgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("long_range_chart_mission") : oo::PList());
				if (bgDescriptor.isNull())
				{
					bgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey(oo::str::format("long_range_chart%d", galaxy_number+1)) : oo::PList());
					if (bgDescriptor.isNull())
					{
						bgDescriptor = (UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey("long_range_chart") : oo::PList());

					}
				}
			}
			break;
		case GUI_BACKGROUND_SPECIAL_NONE:
			break;
		}
		if (!bgDescriptor.isNull())
		{
			setBackgroundTextureDescriptor(bgDescriptor);
		}
	}
	backgroundSpecial = spec;
	refreshStarChart();
}


bool GuiDisplayGen::setBackgroundTextureDescriptor(const oo::PList &descriptor)
{
	backgroundSpecial = GUI_BACKGROUND_SPECIAL_NONE; // reset
	backgroundSprite = NewTextureSpriteWithDescriptor(descriptor, kOOTextureSRGBA);
	return backgroundSprite.get() != nullptr;
}


bool GuiDisplayGen::setForegroundTextureDescriptor(const oo::PList &descriptor)
{
	// FIXME: for some reason passing kOOTextureSRGBA when in SDR results in double gamma correction
	uint32_t srgbaOption = (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->hdrOutput() : false) ? kOOTextureSRGBA : 0;
	foregroundSprite = NewTextureSpriteWithDescriptor(descriptor, srgbaOption);
	return foregroundSprite.get() != nullptr;
}


bool GuiDisplayGen::setBackgroundTextureKey(const std::optional<std::string> &key)
{
	return setBackgroundTextureDescriptor((UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey(key.value_or("")) : oo::PList()));
}


bool GuiDisplayGen::setForegroundTextureKey(const std::optional<std::string> &key)
{
	return setForegroundTextureDescriptor((UNIVERSE != nullptr ? UNIVERSE->screenTextureDescriptorForKey(key.value_or("")) : oo::PList()));
}


bool GuiDisplayGen::preloadGUITexture(const oo::PList &descriptor)
{
	return TextureForGUITexture(descriptor, kOOTextureSRGBA).get() != nil;
}


oo::PList GuiDisplayGen::textureDescriptorFromJSValue(ooscript::Value value,
														   ooscript::Context context,
														   const std::optional<std::string> &callerDescription)
{
	OOJS_PROFILE_ENTER

	oo::PList		result;

	if (ooscript::isObjectOrNull(value))
	{
		// Null may be used to indicate no texture.
		if (ooscript::isNull(value))  return oo::PList(oo::PList::Dict{});

		ooscript::Object objValue = ooscript::toObject(value);

		if (OOJSGetClass(context, objValue) != OOJavaScriptEngine::sharedEngine()->stringClass())
		{
			result = cxx_OOJSDictionaryFromJSObject(context, objValue);
		}
	}

	if (result.isNull())
	{
		const std::optional<std::string> name = cxx_OOStringFromJSValue(context, value);

		if (name.has_value())
		{
			result = oo::PList(oo::PList::Dict{ { "name", oo::PList(*name) } });
			if (name->empty())  return result;	// Explicit empty string may be used to indicate no texture.
		}
	}

	// Start loading the texture, and return nil if it doesn't exist.
	if (!result.isNull() && !preloadGUITexture(result))
	{
		cxx_OOJSReportWarning(context, "%s: texture \"%s\" could not be found.", (callerDescription ? callerDescription->c_str() : "(null)"), DescriptorName(result).value_or("(null)").c_str());
		result = oo::PList();
	}

	return result;

	OOJS_PROFILE_EXIT
}


void GuiDisplayGen::setStatusPage(NSInteger pageNum)
{
	if (pageNum == 0 || (pageNum < 0 && ((NSUInteger)-pageNum) >= statusPage))
	{
		statusPage = 1;
	}
	else
	{
		statusPage += pageNum;
	}
}


NSUInteger GuiDisplayGen::getStatusPage()
{
	return statusPage;
}


void GuiDisplayGen::drawEquipmentList(const oo::PList &eqptList, GLfloat z)
{
	const oo::PList::Array *eqptArray = eqptList.getIf<oo::PList::Array>();
	if (eqptArray == nullptr || eqptArray->empty()) return;

	OOGUIRow		firstRow = STATUS_EQUIPMENT_FIRST_ROW;
	NSUInteger		maxRows = STATUS_EQUIPMENT_MAX_ROWS;
	HeadUpDisplay	*hud = (PLAYER != nullptr ? PLAYER->getHud() : (HeadUpDisplay *)nullptr);
	if (hud != nullptr && hud->getAllowBigGui())	// a nil HUD (or player) answered NO
	{
		maxRows += STATUS_EQUIPMENT_BIGGUI_EXTRA_ROWS;
	}
	NSUInteger		itemsPerColumn = maxRows;


	NSInteger		firstY = 40;	// firstRow =10 :-> 40  - firstRow=11 -> 24 etc...
	NSUInteger		eqptCount = eqptArray->size();
	NSUInteger		pageCount = 1;
	NSUInteger		i;
	NSInteger		start;
	bool			damaged;

	// Paging calculations. Assuming 10 lines we get - one page:20 items per page (ipp)
	// two pages: 18 ipp - three+ pages:  1st & last 18pp,  middle pages 16ipp

	i = itemsPerColumn * 2 + 2;
	if (eqptCount > i) // don't fit in one page?
	{
		if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForUIWithMouseInteraction(YES);

		i = itemsPerColumn * 4; // total items in the first and last pages
		itemsPerColumn--; // for all the middle pages.
		if (eqptCount <= i) // two pages
		{
			pageCount++;
			if (statusPage == 1)
			{
				start = 0;
			}
			else
			{
				statusPage = 2;
				start = i/statusPage; // for the for loop
			}
		}
		else // three or more
		{
			pageCount = ceil((float)(eqptCount-i)/(itemsPerColumn*2)) + 2;
			statusPage = (NSInteger)OOClampInteger(statusPage, 1, pageCount);
			start = (statusPage == 1) ? 0 : (statusPage-1) * itemsPerColumn * 2 + 2;
		}
	}
	else
	{
		statusPage = pageCount; // one page
		start = 0;
		// if we have mouse interaction active, it means that we had more than one
		// pages earlier, but only one now, as e.g. in the case of a hud that wss
		// subsequently hidden, resulting in the equip list fitting in one page,
		// so we need to deactivate it
		if (OOMouseInteractionModeIsUIScreen((UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->mouseInteractionMode() : OOMouseInteractionMode{})))
		{
			// clear the gui-more and gui-back key rows first
			setText("", firstRow);
			setKey("SKIP-ROW", firstRow);
			setText("", firstRow + STATUS_EQUIPMENT_MAX_ROWS);
			setKey("SKIP-ROW", firstRow + STATUS_EQUIPMENT_MAX_ROWS);
			setSelectableRange(NSMakeRange(0,0));

			if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForUIWithMouseInteraction(NO);
		}
	}

	if (statusPage > 1)
	{
		setColor(colorFromSetting(cxx_kGuiStatusEquipmentScrollColor, OOColor::greenColor().get()).get(), firstRow);
		setArray({ OO_DESC("gui-back"), "", " <-- " }, firstRow);
		setKey("OK", firstRow);
		firstY -= 16; // start 1 row down!
		if (statusPage == pageCount)
		{
			setSelectableRange(NSMakeRange(firstRow, 1));
			setSelectedRow(firstRow);
		}
	}
	if (statusPage < pageCount)
	{
		setColor(colorFromSetting(cxx_kGuiStatusEquipmentScrollColor, OOColor::greenColor().get()).get(), firstRow + maxRows);
		setArray({ OO_DESC("gui-more"), "", " --> " }, firstRow + maxRows);
		setKey("OK", firstRow + maxRows);
		if (statusPage == 1)
		{
			setSelectableRange(NSMakeRange(firstRow + maxRows, 1));
			setSelectedRow(firstRow + maxRows);
		}
	}
	if (statusPage > 1 && statusPage < pageCount)
	{
		setSelectableRange(NSMakeRange(firstRow, MIN(firstRow + maxRows, static_cast<NSUInteger>(GUI_DEFAULT_ROWS - firstRow))));
		// default selected row to 'More -->' if we are looking at one of the middle pages
		if (getSelectedRow() == -1)  setSelectedRow(firstRow + maxRows);
	}

	if (statusPage == 1 || statusPage == pageCount) itemsPerColumn++;
	eqptCount = (NSInteger)OOClampInteger(eqptCount, 1, start + itemsPerColumn * 2);
	for (i = start; i < eqptCount; i++)
	{
		const oo::PList &info = (*eqptArray)[i];
		std::string name = info.at<std::string>(0);
		if (oo::str::length(name) > 42)
		{
			name = oo::utf16ToUtf8(oo::utf8ToUtf16(name).substr(0, 40)) + "...";
		}

		damaged = !info.at<bool>(1);
		if (damaged)
		{
			// Damaged items show up orange.
			setGLColorFromSetting("status_equipment_damaged_color", OOColor::orangeColor().get(), 1.0);
		}
		else /// add color selection here
		{
			::OOColor *dispCol = nil;
			if (const oo::PList::Array *row = info.getIf<oo::PList::Array>())
			{
				if (row->size() > 2)  dispCol = OOColorInObjectNode((*row)[2]);
			}
			// Normal items in default colour
			setGLColorFromSetting("status_equipment_ok_color", dispCol, 1.0);
		}

		if (i - start < itemsPerColumn)
		{
			cxx_OODrawString(name, -220, firstY - 16 * (NSInteger)(i - start), z, NSMakeSize(15, 15));
		}
		else
		{
			cxx_OODrawString(name, 50, firstY - 16 * (NSInteger)(i - itemsPerColumn - start), z, NSMakeSize(15, 15));
		}
	}
}


void GuiDisplayGen::drawGUIBackground()
{
	GLfloat x = drawPosition.x;
	GLfloat y = drawPosition.y;
	GLfloat z = (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getDisplay_z() : 0.0f);

	if (backgroundSprite.get()!=nullptr)
	{
		backgroundSprite->blitBackgroundCentredToX(x, y, z, 1.0f);
	}
	
}


void GuiDisplayGen::refreshStarChart()
{
	_refreshStarChart = YES;
}


int GuiDisplayGen::drawGUI(GLfloat alpha, bool drawCursor)
{
	GLfloat x = drawPosition.x;
	GLfloat y = drawPosition.y;
	GLfloat z = (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getDisplay_z() : 0.0f);
	
	if (alpha > 0.05f)
	{
		::PlayerEntity* player = PLAYER;
		
		drawGLDisplay(x - 0.5f * size_in_pixels.width, y - 0.5f * size_in_pixels.height, z, alpha);
		
		if (this == (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr))
		{
			if ((player != nullptr ? player->guiScreen() : OOGUIScreenID{}) == GUI_SCREEN_SHORT_RANGE_CHART || (player != nullptr ? player->guiScreen() : OOGUIScreenID{}) == GUI_SCREEN_LONG_RANGE_CHART || 
				backgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT ||
				backgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT_ANA_QUICKEST ||
				backgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT_ANA_SHORTEST ||
				backgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM ||
				backgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_QUICKEST ||
				backgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_SHORTEST)
			{
				drawStarChart(x - 0.5f * size_in_pixels.width, y - 0.5f * size_in_pixels.height, z, alpha, NO);
			}
			if (backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG || 
					backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST ||
					backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST)
			{
				drawStarChart(x - 0.5f * size_in_pixels.width, y - 0.5f * size_in_pixels.height, z, alpha, YES);
			}
			if ((player != nullptr ? player->guiScreen() : OOGUIScreenID{}) == GUI_SCREEN_STATUS)
			{
				drawEquipmentList(oo::PList((player != nullptr ? player->equipmentList() : std::vector<oo::PList>())), z);
			}
			if ((player != nullptr ? player->guiScreen() : OOGUIScreenID{}) == GUI_SCREEN_STICKPROFILE)
			{
				if (player != nullptr)  player->stickProfileGraphAxisProfile(alpha, make_vector(x,y,z), size_in_pixels);
			}
		}
		
		if (fade_sign)
		{
			fade_alpha += (float)(fade_sign * (UNIVERSE != nullptr ? UNIVERSE->getTimeDelta() : 0.0));
			if (fade_alpha < 0.05f)	// done fading out
			{
				fade_alpha = 0.0f;
				fade_sign = 0.0f;
			}
			if (fade_alpha >= max_alpha)	// done fading in
			{
				fade_alpha = max_alpha;
				fade_sign = 0.0f;
			}
		}
	}
	
	int cursor_row = 0;

	if (drawCursor)
	{
		NSPoint vjpos = (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->getVirtualJoystickPosition() : NSPoint{});
		double cursor_x = size_in_pixels.width * vjpos.x;
		if (cursor_x < -size_in_pixels.width * 0.5)  cursor_x = -size_in_pixels.width * 0.5f;
		if (cursor_x > size_in_pixels.width * 0.5)   cursor_x = size_in_pixels.width * 0.5f;
		double cursor_y = -size_in_pixels.height * vjpos.y;
		if (cursor_y < -size_in_pixels.height * 0.5)  cursor_y = -size_in_pixels.height * 0.5f;
		if (cursor_y > size_in_pixels.height * 0.5)   cursor_y = size_in_pixels.height * 0.5f;

		cursor_row = rowAtVirtualJoystickPosition(vjpos);

		GLfloat h1 = 3.0f;
		GLfloat h3 = 9.0f;
		OOGL(glColor4f(0.6f, 0.6f, 1.0f, 1.0f)); // original value of (0.2f, 0.2f, 1.0f, 0.5f) too dark - Nikos 20130616
		OOGL(GLScaledLineWidth(2.0f));
		
		cursor_x += x;
		cursor_y += y;
		if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->setVirtualJoystick(cursor_x/size_in_pixels.width, -cursor_y/size_in_pixels.height);

		OOGLBEGIN(GL_LINES);
			glVertex3f((float)cursor_x - h1, (float)cursor_y, z);	glVertex3f((float)cursor_x - h3, (float)cursor_y, z);
			glVertex3f((float)cursor_x + h1, (float)cursor_y, z);	glVertex3f((float)cursor_x + h3, (float)cursor_y, z);
			glVertex3f((float)cursor_x, (float)cursor_y - h1, z);	glVertex3f((float)cursor_x, (float)cursor_y - h3, z);
			glVertex3f((float)cursor_x, (float)cursor_y + h1, z);	glVertex3f((float)cursor_x, (float)cursor_y + h3, z);
		OOGLEND();
		OOGL(GLScaledLineWidth(1.0f));
		
	}
	
	return cursor_row;
}


void GuiDisplayGen::drawGLDisplay(GLfloat x, GLfloat y, GLfloat z, GLfloat alpha)
{
	NSSize		strsize;
	unsigned	i;
	OOTimeDelta	delta_t = (UNIVERSE != nullptr ? UNIVERSE->getTimeDelta() : 0.0);
	NSSize		characterSize = pixel_text_size;
	NSSize		titleCharacterSize = pixel_title_size;
	float		backgroundAlpha = this == (UNIVERSE != nullptr ? UNIVERSE->messageGUI() : nullptr) && !(UNIVERSE != nullptr ? UNIVERSE->permanentMessageLog() : false) ? 0.0f : alpha;
	std::vector<float>	row_alpha(n_rows);
	
	// calculate fade out time and alpha for each row. Do it before
	// applying a potential background because we need the maximum alpha
	// of all rows to be the alpha applied to the background color
	for (i = 0; i < n_rows; i++)
	{
		row_alpha[i] = alpha;
		
		if(!(UNIVERSE != nullptr ? UNIVERSE->autoMessageLogBg() : false) && (PLAYER != nullptr ? PLAYER->guiScreen() : OOGUIScreenID{}) == GUI_SCREEN_MAIN)  backgroundAlpha = alpha;
		
		if (rowFadeTime[i] > 0.0f && !(UNIVERSE != nullptr ? UNIVERSE->permanentMessageLog() : false))
		{
			rowFadeTime[i] -= (float)delta_t;
			if (rowFadeTime[i] <= 0.0f)
			{
				rowText[i] = oo::PList("");
				rowFadeTime[i] = 0.0f;
				continue;
			}
			if ((rowFadeTime[i] > 0.0f)&&(rowFadeTime[i] < 1.0))
			{
				row_alpha[i] *= rowFadeTime[i];
				if (backgroundAlpha < row_alpha[i])  backgroundAlpha = row_alpha[i];
			}
			else
			{
				backgroundAlpha = alpha;
			}
		}
	}
	
	// do backdrop
	// don't draw it if docked, unless message_gui is permanent
	// don't draw it on the intro screens
	if (backgroundColor.get())
	{
		int playerStatus = (PLAYER != nullptr ? PLAYER->status() : OOEntityStatus{});
		if (playerStatus != STATUS_START_GAME && playerStatus != STATUS_DEAD)
		{
			OOGL(glColor4f(backgroundColor->redComponent(), backgroundColor->greenComponent(), backgroundColor->blueComponent(), backgroundAlpha * backgroundColor->alphaComponent()));
			OOGLBEGIN(GL_QUADS);
				glVertex3f(x + 0.0f,					y + 0.0f,					z);
				glVertex3f(x + size_in_pixels.width,	y + 0.0f,					z);
				glVertex3f(x + size_in_pixels.width,	y + size_in_pixels.height,	z);
				glVertex3f(x + 0.0f,					y + size_in_pixels.height,	z);
			OOGLEND();
		}
	}
	
	// show the 'foreground', aka overlay!
	
	if (foregroundSprite.get() != nullptr)
	{
		foregroundSprite->blitCentredToX(x + 0.5f * size_in_pixels.width, y + 0.5f * size_in_pixels.height, z, alpha);
	}
	
	if (!RowInRange(selectedRow, selectableRange))
		selectedRow = -1;   // out of Range;
	
	////
	// drawing operations here
	
	if (title.has_value())
	{
		//
		// draw the title
		//
		strsize = cxx_OORectFromString(*title, 0.0f, 0.0f, titleCharacterSize).size;
		setGLColorFromSetting(cxx_kGuiScreenTitleColor, OOColor::redColor().get(), alpha);

		cxx_OODrawString(*title, x + pixel_row_center - strsize.width/2.0, y + size_in_pixels.height - pixel_title_size.height, z, titleCharacterSize);
		
		// draw a horizontal divider
		//
		setGLColorFromSetting(cxx_kGuiScreenDividerColor, OOColor::colorWithWhite(0.75, 1.0).get(), alpha);

		OOGLBEGIN(GL_QUADS);
			glVertex3f(x + 0,					y + size_in_pixels.height - pixel_title_size.height + 4,	z);
			glVertex3f(x + size_in_pixels.width,	y + size_in_pixels.height - pixel_title_size.height + 4,	z);
			glVertex3f(x + size_in_pixels.width,	y + size_in_pixels.height - pixel_title_size.height + 2,		z);
			glVertex3f(x + 0,					y + size_in_pixels.height - pixel_title_size.height + 2,		z);
		OOGLEND();
	}
	
	// draw each row of text
	//
	OOStartDrawingStrings();
	for (i = 0; i < n_rows; i++)
	{
		::OOColor* row_color = rowColor[i].get();
		if (row_color != nullptr)  glColor4f(row_color->redComponent(), row_color->greenComponent(), row_color->blueComponent(), row_alpha[i]);
		else  glColor4f(0.0f, 0.0f, 0.0f, row_alpha[i]);	// a nil colour answered zeros
		
		if (const std::string *rowString = rowText[i].getIf<std::string>())
		{
			const std::string &text = *rowString;
			if (!text.empty())
			{
				strsize = cxx_OORectFromString(text, 0.0f, 0.0f, characterSize).size;
				switch (rowAlignment[i])
				{
					case GUI_ALIGN_LEFT :
						rowPosition[i].x = 0.0f;
						break;
					case GUI_ALIGN_RIGHT :
						rowPosition[i].x = size_in_pixels.width - strsize.width;
						break;
					case GUI_ALIGN_CENTER :
						rowPosition[i].x = (size_in_pixels.width - strsize.width)/2.0f;
						break;
				}
				if (i == (unsigned)selectedRow)
				{
					NSRect		block = cxx_OORectFromString(text, x + rowPosition[i].x + 2, y + rowPosition[i].y + 2, characterSize);
					OOStopDrawingStrings();
					setGLColorFromSetting(cxx_kGuiSelectedRowBackgroundColor, OOColor::redColor().get(), alpha);
					OOGLBEGIN(GL_QUADS);
						glVertex3f(block.origin.x,						block.origin.y,						z);
						glVertex3f(block.origin.x + block.size.width,	block.origin.y,						z);
						glVertex3f(block.origin.x + block.size.width,	block.origin.y + block.size.height,	z);
						glVertex3f(block.origin.x,						block.origin.y + block.size.height,	z);
					OOGLEND();
					setGLColorFromSetting(cxx_kGuiSelectedRowColor, OOColor::blackColor().get(), alpha);
					OOStartDrawingStrings();
				}
				cxx_OODrawStringQuadsAligned(text, x + rowPosition[i].x, y + rowPosition[i].y, z, characterSize, NO);

				// draw cursor at end of current Row
				//
				if ((showTextCursor)&&(i == (unsigned)currentRow))
				{
					NSRect	tr = cxx_OORectFromString(text, 0.0f, 0.0f, characterSize);
					NSPoint cu = NSMakePoint(x + rowPosition[i].x + tr.size.width + 0.2f * characterSize.width, y + rowPosition[i].y);
					tr.origin = cu;
					tr.size.width = 0.5f * characterSize.width;
					GLfloat g_alpha = 0.5f * (1.0f + (float)sin(6 * (UNIVERSE != nullptr ? UNIVERSE->getTime() : 0.0)));
					OOStopDrawingStrings();
					setGLColorFromSetting(cxx_kGuiTextInputCursorColor, OOColor::redColor().get(), row_alpha[i]*g_alpha);
					OOGLBEGIN(GL_QUADS);
						glVertex3f(tr.origin.x,					tr.origin.y,					z);
						glVertex3f(tr.origin.x + tr.size.width,	tr.origin.y,					z);
						glVertex3f(tr.origin.x + tr.size.width,	tr.origin.y + tr.size.height,	z);
						glVertex3f(tr.origin.x,					tr.origin.y + tr.size.height,	z);
					OOGLEND();
					OOStartDrawingStrings();
				}
			}
		}
		if (rowText[i].isArray())
		{
			const oo::PList	&array = rowText[i];
			NSUInteger	j, max_columns = MIN(array.count(), n_columns);
			BOOL		isLeftAligned;

			for (j = 0; j < max_columns; j++)
			{
				const std::string text = array.at<std::string>(j);	// -oo_stringAtIndex: ("" for none)
				if (text.size() != 0)
				{
					isLeftAligned = tabStops[j] >= 0;
					rowPosition[i].x = llabs(tabStops[j]);

					// we don't want to highlight leading space(s) or narrow spaces (\037s)
					std::string	hilitedText = TrimmedForHighlight(text);
					// -rangeOfString: of an empty string answered NSNotFound.
					const std::size_t	txtLocation = hilitedText.empty() ? std::string::npos : text.find(hilitedText);
					unsigned	leadingSpaces = 0;

					if (EXPECT_NOT(txtLocation == std::string::npos))
					{
						// This never happens!
						hilitedText = text;
					}
					else if (txtLocation > 0)
					{
						// padded string! (the padding is ASCII, so its bytes are its characters)
						NSRect charBlock = cxx_OORectFromString(text.substr(0, txtLocation), 0, 0, characterSize);
						leadingSpaces = (unsigned)charBlock.size.width;

/*						// if we're displaying commodity-quantity-none, let's try and be pixel perfect!
						std::string qtyNone = OO_DESC("commodity-quantity-none");
						txtRange = [hilitedText rangeOfString:qtyNone];
						
						if (txtRange.location == 0) // bingo!
						{
							rowPosition[i].x += OORectFromString(@"0", 0, 0, characterSize).size.width - OORectFromString(qtyNone, 0, 0, characterSize).size.width;
							} */
					}
					
					// baseline text rect, needed for correct highlight positioning.
					NSRect		block = cxx_OORectFromString(text, x + rowPosition[i].x + 2, y + rowPosition[i].y + 2, characterSize);

					if(!isLeftAligned)
					{
						rowPosition[i].x -= block.size.width + 3;
					}
					block = cxx_OORectFromString(hilitedText, x + rowPosition[i].x + 1 + leadingSpaces, y + rowPosition[i].y + 2, characterSize);
					block.size.width += 3;
						
					
					if (i == (unsigned)selectedRow)
					{
						OOStopDrawingStrings();
						setGLColorFromSetting(cxx_kGuiSelectedRowBackgroundColor, OOColor::redColor().get(), alpha);
						OOGLBEGIN(GL_QUADS);
							glVertex3f(block.origin.x,						block.origin.y,						z);
							glVertex3f(block.origin.x + block.size.width,	block.origin.y,						z);
							glVertex3f(block.origin.x + block.size.width,	block.origin.y + block.size.height,	z);
							glVertex3f(block.origin.x,						block.origin.y + block.size.height,	z);
						OOGLEND();
						setGLColorFromSetting(cxx_kGuiSelectedRowColor, OOColor::blackColor().get(), alpha);
						OOStartDrawingStrings();
					}
					cxx_OODrawStringQuadsAligned(text, x + rowPosition[i].x, y + rowPosition[i].y, z, characterSize,NO);
				}
			}
		}
	}
	OOStopDrawingStrings();
	OOTexture::applyNone();
}


void GuiDisplayGen::drawCrossHairsWithSize(GLfloat size, GLfloat x, GLfloat y, GLfloat z)
{
	OOGLBEGIN(GL_QUADS);
		glVertex3f(x - 1,	y - size,	z);
		glVertex3f(x + 1,	y - size,	z);
		glVertex3f(x + 1,	y + size,	z);
		glVertex3f(x - 1,	y + size,	z);
		glVertex3f(x - size,	y - 1,	z);
		glVertex3f(x + size,	y - 1,	z);
		glVertex3f(x + size,	y + 1,	z);
		glVertex3f(x - size,	y + 1,	z);
	OOGLEND();
}


void GuiDisplayGen::setStarChartTitle()
{
	::PlayerEntity *player = PLAYER;
	OOGalaxyID galaxy_number = (player != nullptr ? player->galaxyNumber() : OOGalaxyID{});
	NSInteger system_id = (UNIVERSE != nullptr ? UNIVERSE->findSystemNumberAtCoords((player != nullptr ? player->getCursor_coordinates() : NSPoint{}), (player != nullptr ? player->galaxyNumber() : OOGalaxyID{}), NO) : 0);

	const std::string location_key = oo::str::format("long-range-chart-title-%d-%ld", galaxy_number, (long)system_id);
	if (!(UNIVERSE != nullptr ? UNIVERSE->descriptionForKey(location_key) : std::optional<std::string>()))
	{
		const std::string gal_key = oo::str::format("long-range-chart-title-%d", galaxy_number);
		if (!(UNIVERSE != nullptr ? UNIVERSE->descriptionForKey(gal_key) : std::optional<std::string>()))
		{
			setTitle(oo::str::formatRuntime(OO_DESC("long-range-chart-title-d"), { galaxy_number + 1 }));
		}
		else
		{
			setTitle((UNIVERSE != nullptr ? UNIVERSE->descriptionForKey(gal_key) : std::optional<std::string>()));
		}
	}
	else
	{
		setTitle((UNIVERSE != nullptr ? UNIVERSE->descriptionForKey(location_key) : std::optional<std::string>()));
	}
}


void GuiDisplayGen::drawSystemMarkers(const oo::PList &markers, GLfloat x, GLfloat y, GLfloat z, GLfloat alpha, GLfloat scale)
{
	const oo::PList::Array *markerList = markers.getIf<oo::PList::Array>();
	if (markerList == nullptr)  return;
	for (const oo::PList &marker : *markerList)
	{
		drawSystemMarker(marker, x, y, z, alpha, scale);
	}
}


void GuiDisplayGen::drawSystemMarker(const oo::PList &marker, GLfloat x, GLfloat y, GLfloat z, GLfloat alpha, GLfloat scale)
{
	const std::string colorDesc = marker.get<std::string>("markerColor", "redColor");
	const oo::Ref<OOColor> markerColor = OOColor::colorWithDescription(oo::PList(colorDesc));
	OORGBAComponents color = (markerColor != nullptr) ? markerColor->rgbaComponents() : OORGBAComponents{};	// a nil colour answered zeros
	
	OOGL(glColor4f(color.r, color.g, color.b, alpha));	// red
	GLfloat mark_size = marker.get<float>("markerScale", 1.0);
	if (mark_size > 2.0)
	{
		mark_size = 2.0;
	}
	else if (mark_size < 0.5)
	{
		mark_size = 0.5;
	}
	mark_size *= scale;

	const std::string shape = marker.get<std::string>("markerShape", "MARKER_X");

	OOGLBEGIN(GL_LINES);
	if (shape == "MARKER_X")
	{
		glVertex3f(x - mark_size,	y - mark_size,	z);
		glVertex3f(x + mark_size,	y + mark_size,	z);
		glVertex3f(x - mark_size,	y + mark_size,	z);
		glVertex3f(x + mark_size,	y - mark_size,	z);
	}
	else if (shape == "MARKER_PLUS")
	{
		mark_size *= 1.4; // match volumes
		glVertex3f(x,	y - mark_size,	z);
		glVertex3f(x,	y + mark_size,	z);
		glVertex3f(x - mark_size,	y,	z);
		glVertex3f(x + mark_size,	y,	z);
	}
	else if (shape == "MARKER_SQUARE")
	{
		glVertex3f(x - mark_size,	y - mark_size,	z);
		glVertex3f(x - mark_size,	y + mark_size,	z);
		glVertex3f(x - mark_size,	y + mark_size,	z);
		glVertex3f(x + mark_size,	y + mark_size,	z);
		glVertex3f(x + mark_size,	y + mark_size,	z);
		glVertex3f(x + mark_size,	y - mark_size,	z);
		glVertex3f(x + mark_size,	y - mark_size,	z);
		glVertex3f(x - mark_size,	y - mark_size,	z);
	}
	else if (shape == "MARKER_DIAMOND")
	{
		mark_size *= 1.4; // match volumes
		glVertex3f(x,	y - mark_size,	z);
		glVertex3f(x - mark_size,	y,	z);
		glVertex3f(x - mark_size,	y,	z);
		glVertex3f(x,	y + mark_size,	z);
		glVertex3f(x,	y + mark_size,	z);
		glVertex3f(x + mark_size,	y,	z);
		glVertex3f(x + mark_size,	y,	z);
		glVertex3f(x,	y - mark_size,	z);
	}
	OOGLEND();
}


OOSystemID GuiDisplayGen::targetNextFoundSystem(int direction) // +1 , 0 , -1
{
	OOSystemID sys = (PLAYER != nullptr ? PLAYER->targetSystemID() : 0);
	if ((PLAYER != nullptr ? PLAYER->guiScreen() : OOGUIScreenID{}) != GUI_SCREEN_SHORT_RANGE_CHART && (PLAYER != nullptr ? PLAYER->guiScreen() : OOGUIScreenID{}) != GUI_SCREEN_LONG_RANGE_CHART) return sys;
	
	BOOL		*systemsFound = (UNIVERSE != nullptr ? UNIVERSE->systemsFound() : nullptr);
	unsigned 	i, first = 0, last = 0, count = 0;
	int 		systemIndex = foundSystem + direction;
	
	if (direction == 0) systemIndex = 0;
	
	for (i = 0; i <= kOOMaximumSystemID; i++)
	{
		if (systemsFound[i])
		{
			if (count == 0)
			{
				first = last = i;
			}
			else
			{
				last = i;
			}
			if (systemIndex == (int)count) 
			{
				sys = i;
			}
			count++;
		}
	}
	
	if (count == 0) return sys; // empty systemFound list.
	
	// loop back if needed.
	if (systemIndex < 0)
	{
		systemIndex = count - 1;
		sys = last;
	}
	if (systemIndex >= (int)count)
	{
		systemIndex = 0;
		sys = first;
	}
	
	foundSystem = systemIndex;
	return sys;
}


// Advanced Navigation Array -- galactic chart route mapping - contributed by Nikos Barkas (another_commander).
void GuiDisplayGen::drawAdvancedNavArrayAtX(float x, float y, float z, float alpha, const oo::PList &routeInfo, OORouteType optimizeBy, OOScalar zoom)
{
	GLfloat lr,lg,lb,la,lr2,lg2,lb2,la2;
	double			hscale = size_in_pixels.width / (CHART_WIDTH_AT_MAX_ZOOM*zoom);
	double			vscale = -1.0 * size_in_pixels.height / (2*CHART_HEIGHT_AT_MAX_ZOOM*zoom);
	NSPoint			star = NSZeroPoint, 
		star2 = NSZeroPoint, 
		starabs = NSZeroPoint, 
		star2abs = NSZeroPoint;
	::OOSystemDescriptionManager *systemManager = (UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr);
	OOGalaxyID		g = (PLAYER != nullptr ? PLAYER->galaxyNumber() : OOGalaxyID{});
	OOSystemID planetNumber = (PLAYER != nullptr ? PLAYER->systemID() : 0);

	oo::Ref<OOColor>	defaultConnectionColor = colorFromSetting(cxx_kGuiChartConnectionColor, OOColor::colorWithWhite(0.25, 1.0).get());
	oo::Ref<OOColor>	currentJumpColorStart = colorFromSetting(cxx_kGuiChartCurrentJumpStartColor, OOColor::colorWithWhite(0.25, 0.0).get());
	oo::Ref<OOColor>	currentJumpColorEnd = colorFromSetting(cxx_kGuiChartCurrentJumpEndColor, OOColor::colorWithWhite(0.25, 0.0).get());

	oo::Ref<OOColor>	thisConnectionColor;
	oo::Ref<OOColor>	thatConnectionColor;
	
	float jumpRange = MAX_JUMP_RANGE * ((optimizeBy == OPTIMIZED_BY_NONE) ? (PLAYER != nullptr ? PLAYER->dialFuel() : 0.0f) : 1.0);

	NSInteger concealment[256];
	for (NSUInteger i=0;i<256;i++) {
		concealment[i] = systemManager->getPropertiesForSystem(i, g).get<int>("concealment", OO_SYSTEMCONCEALMENT_NONE);
	}

	
	OOGLBEGIN(GL_LINES);
	for (OOSystemID i = 0; i < 256; i++)
	{

		if (concealment[i] >= OO_SYSTEMCONCEALMENT_NOTHING) {
			// system is not known
			continue;
		}
		
		/* Concealment */
		if (optimizeBy == OPTIMIZED_BY_NONE && i != planetNumber)
		{
			continue;
		}

		starabs = systemManager->getCoordinatesForSystem(i, g);

		star.x = (float)(starabs.x * hscale);
		star.y = (float)(starabs.y * vscale);

		// if in non-route mode, we're always starting from i, so need
		// to do <i here too.
		OOSystemID loopstart = (optimizeBy == OPTIMIZED_BY_NONE) ? 0 : (i+1);

		for (OOSystemID j = loopstart; j < 256; j++)
		{
			if (i == j)
			{
				continue; // for OPTIMIZED_BY_NONE case
			}

			if (concealment[j] >= OO_SYSTEMCONCEALMENT_NOTHING) {
				// system is not known
				continue;
			}
			
			star2abs = systemManager->getCoordinatesForSystem(j, g);
			double d = distanceBetweenPlanetPositions(starabs.x, starabs.y, star2abs.x, star2abs.y);
		
			if (d <= jumpRange)	// another_commander - Default to 7.0 LY.
			{
				star2.x = (float)(star2abs.x * hscale);
				star2.y = (float)(star2abs.y * vscale);
				if (optimizeBy == OPTIMIZED_BY_NONE)
				{
					currentJumpColorStart->getRed(&lr, &lg, &lb, &la);
					currentJumpColorEnd->getRed(&lr2, &lg2, &lb2, &la2);
					OOGL(glColor4f(lr, lg, lb, la*alpha));
					glVertex3f(x+star.x, y+star.y, z);

					float frac = (d/jumpRange);
					OOGL(glColor4f(
							 OOLerp(lr,lr2,frac),
							 OOLerp(lg,lg2,frac),
							 OOLerp(lb,lb2,frac),
							 OOLerp(la,la2,frac)
							 ));
					glVertex3f(x+star2.x, y+star2.y, z);

				}
				else
				{
					thisConnectionColor = OOColor::colorWithDescription(systemManager->getProperty("link_color", oo::str::format("interstellar: %d %ld %ld", g, (long)i, (long)j)));
				
					if (thisConnectionColor == nil)
					{
						thisConnectionColor = defaultConnectionColor;
					}
					thisConnectionColor->getRed(&lr, &lg, &lb, &la);
					OOGL(glColor4f(lr, lg, lb, la*alpha));

					glVertex3f(x+star.x, y+star.y, z);

					// and the other colour for the other end
					thatConnectionColor = OOColor::colorWithDescription(systemManager->getProperty("link_color", oo::str::format("interstellar: %d %ld %ld", g, (long)j, (long)i)));
				
					if (thatConnectionColor == nil)
					{
						thatConnectionColor = thisConnectionColor;
					}
					thatConnectionColor->getRed(&lr, &lg, &lb, &la);
					OOGL(glColor4f(lr, lg, lb, la*alpha));

					glVertex3f(x+star2.x, y+star2.y, z);
				}
			}
		}
	}
	OOGLEND();
	
	if (optimizeBy == OPTIMIZED_BY_NONE)
	{
		return;
	}

	if (!routeInfo.isNull())
	{
		// "route" as -oo_arrayForKey: read it (its count: 0 when it is not an array), and as
		// -objectForKey: gave it to the index reads (null reads as 0, as messaging nil did).
		const oo::PList *routeArray = routeInfo.get<oo::PList::Array>("route");
		const oo::PList route = (routeInfo.find("route") != nullptr) ? *routeInfo.find("route") : oo::PList();
		NSUInteger i, route_hops = ((routeArray != nullptr) ? routeArray->count() : 0) - 1;
		
		if (optimizeBy == OPTIMIZED_BY_JUMPS)
		{
			// route optimised by distance
			setGLColorFromSetting(cxx_kGuiChartRouteShortColor, OOColor::yellowColor().get(), alpha);
		}
		else
		{
			// route optimised by time
			setGLColorFromSetting(cxx_kGuiChartRouteQuickColor, OOColor::cyanColor().get(), alpha);
		}
		OOSystemID loc;
		for (i = 0; i < route_hops; i++)
		{
			loc = route.at<int>(i);
			starabs = systemManager->getCoordinatesForSystem(loc, g);
			star2abs = systemManager->getCoordinatesForSystem(route.at<int>(i+1), g);

			star.x = (float)(starabs.x * hscale);
			star.y = (float)(starabs.y * vscale);
			
			star2.x = (float)(star2abs.x * hscale);
			star2.y = (float)(star2abs.y * vscale);

			
			OOGLBEGIN(GL_LINES);
				glVertex3f(x+star.x, y+star.y, z);
				glVertex3f(x+star2.x, y+star2.y, z);
			OOGLEND();
			
			// Label the route, if not already labelled
			if (zoom > CHART_ZOOM_SHOW_LABELS && concealment[loc] < OO_SYSTEMCONCEALMENT_NONAME)
			{
				cxx_OODrawString((UNIVERSE != nullptr ? UNIVERSE->systemNameIndex(loc) : std::optional<std::string>()).value_or(""), x + star.x + 2.0, y + star.y, z, NSMakeSize(8,8));
			}
		}
		// Label the destination, which was not included in the above loop.
		if (zoom > CHART_ZOOM_SHOW_LABELS)
		{
			loc = route.at<int>(i);
			if(concealment[loc] < OO_SYSTEMCONCEALMENT_NONAME)
			{
				cxx_OODrawString((UNIVERSE != nullptr ? UNIVERSE->systemNameIndex(loc) : std::optional<std::string>()).value_or(""), x + star2.x + 2.0, y + star2.y, z, NSMakeSize(10,10));
			}
		}
	}
}


void GuiDisplayGen::drawStarChart(GLfloat x, GLfloat y, GLfloat z, GLfloat alpha, bool compact)
{
	::PlayerEntity* player = PLAYER;

	if (!player)
		return;

	::OOSystemDescriptionManager *systemManager = (UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr);

	OOScalar	zoom = (player != nullptr ? player->getChart_zoom() : OOScalar{});
	NSPoint	chart_centre_coordinates = (player != nullptr ? player->adjusted_chart_centre() : NSPoint{});
	NSPoint	galaxy_coordinates = (player != nullptr ? player->getGalaxy_coordinates() : NSPoint{});
	NSPoint	cursor_coordinates = (player != nullptr ? player->getCursor_coordinates() : NSPoint{});
	NSPoint info_system_coordinates = ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getCoordinatesForSystem((player != nullptr ? player->infoSystemID() : 0), (player != nullptr ? player->galaxyNumber() : OOGalaxyID{})) : NSMakePoint(0, 0));
	OOLongRangeChartMode chart_mode = (player != nullptr ? player->getLongRangeChartMode() : OOLongRangeChartMode{});
	OOGalaxyID		galaxy_id = (player != nullptr ? player->galaxyNumber() : OOGalaxyID{});
	GLfloat			r = 1.0, g = 1.0, b = 1.0;
	BOOL			noNova;
	NSPoint	cu;
	NSUInteger		systemParameter;

	double fuel = 35.0 * (player != nullptr ? player->dialFuel() : 0.0f);
	
	double		hcenter = size_in_pixels.width/2.0;
	double		hscale = size_in_pixels.width / (CHART_WIDTH_AT_MAX_ZOOM*zoom);
	double		vscale = -size_in_pixels.height / (2*CHART_HEIGHT_AT_MAX_ZOOM*zoom);
	double		vcenter = CHART_SCREEN_VERTICAL_CENTRE;
	double		hoffset = hcenter - chart_centre_coordinates.x*hscale;
	double		voffset = size_in_pixels.height - vcenter - chart_centre_coordinates.y*vscale;

	if (compact)
	{
		hscale = size_in_pixels.width / 256.0;
		vscale = -1.0 * size_in_pixels.height / 512.0;
		hoffset = 0.0f;
		voffset = size_in_pixels.height - pixel_title_size.height - 5;
		vcenter = CHART_SCREEN_VERTICAL_CENTRE_COMPACT;
		chart_centre_coordinates.x = 128.0;
		chart_centre_coordinates.y = 128.0;
		zoom = CHART_MAX_ZOOM;
	}
	
	int			i;
	double		d, distance = 0.0, time = 0.0;
	int		jumps = 0;
	NSPoint		star;
	OOScalar	pixelRatio;
	NSRect		clipRect;
	
	OORouteType	advancedNavArrayMode = (player != nullptr ? player->ANAMode() : OORouteType{});
	BOOL		routeExists = NO;

	NSInteger concealment[256];
	for (i=0;i<256;i++) {
		const oo::PList systemInfo = systemManager->getPropertiesForSystem(i, galaxy_id);
		concealment[i] = systemInfo.get<int>("concealment", OO_SYSTEMCONCEALMENT_NONE);
	}
	
	BOOL		*systemsFound = (UNIVERSE != nullptr ? UNIVERSE->systemsFound() : nullptr);
	NSSize		viewSize = (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr ? UNIVERSE->getGameView()->backingViewSize() : NSSize{});
	double aspect_ratio = viewSize.width / viewSize.height;

	// default colours - match those in HeadUpDisplay:OODrawPlanetInfo
	GLfloat govcol[] = {	0.5, 0.0, 0.7,
							0.7, 0.5, 0.3,
							0.0, 1.0, 0.3,
							1.0, 0.8, 0.1,
							1.0, 0.0, 0.0,
							0.1, 0.5, 1.0,
							0.7, 0.7, 0.7,
							0.7, 1.0, 1.0};

	if (aspect_ratio > 4.0/3.0)
	{
		pixelRatio = viewSize.height / 480.0;
	}
	else
	{
		pixelRatio = viewSize.width / 640.0;
	}

	NSInteger textRow = compact ? GUI_ROW_CHART_SYSTEM_COMPACT : GUI_ROW_CHART_SYSTEM;
	
	clipRect = NSMakeRect((viewSize.width - size_in_pixels.width*pixelRatio)/2.0,
				(viewSize.height + size_in_pixels.height*pixelRatio)/2.0 - (pixel_title_size.height + 15 + (textRow-2)*MAIN_GUI_ROW_HEIGHT) * pixelRatio,
				size_in_pixels.width * pixelRatio,
				(textRow-1) * MAIN_GUI_ROW_HEIGHT * pixelRatio);

	OOSystemID target = (PLAYER != nullptr ? PLAYER->targetSystemID() : 0);
	double dx, dy;
	
	// get a list of systems marked as contract destinations
	const std::optional<std::map<int, std::vector<oo::PList>>> markedDestinations = (player != nullptr ? player->markedDestinations() : std::optional<std::map<int, std::vector<oo::PList>>>());
	
	// get present location
	cu = NSMakePoint((float)(hscale*galaxy_coordinates.x+hoffset),(float)(vscale*galaxy_coordinates.y+voffset));

	// enable draw clipping; limit drawing area within the chart area
	OOGL(glEnable(GL_SCISSOR_TEST));
	OOGL(glScissor(clipRect.origin.x, clipRect.origin.y, clipRect.size.width, clipRect.size.height));

	// Cache nearby systems so that [UNIVERSE generateSystemData:] does not get called on every frame
	// Caching code submitted by Y A J, 20091022
	
	static OOGalaxyID saved_galaxy_id;
	static struct saved_system
	{
		OOSystemID sysid;
		int tec, eco, gov;
		std::string p_name;
		BOOL nova;
	} nearby_systems[ 256 ];
	static int num_nearby_systems = 0;

	if ( _refreshStarChart || galaxy_id != saved_galaxy_id)
	{
		// saved systems are stale; recompute
		_refreshStarChart = NO;

		num_nearby_systems = 0;
		for (i = 0; i < 256; i++)
		{

			const oo::PList sys_info = (UNIVERSE != nullptr ? UNIVERSE->generateSystemData(i) : oo::PList());
			if (EXPECT_NOT(sys_info.get<bool>("sun_gone_nova")))
			{
				nearby_systems[ num_nearby_systems ].gov = -1;	// Flag up nova systems!
			}
			else
			{
				nearby_systems[ num_nearby_systems ].tec = sys_info.get<int>(std::string(KEY_TECHLEVEL));
				nearby_systems[ num_nearby_systems ].eco = sys_info.get<int>(std::string(KEY_ECONOMY));
				nearby_systems[ num_nearby_systems ].gov = sys_info.get<int>(std::string(KEY_GOVERNMENT));
			}
			nearby_systems[ num_nearby_systems ].sysid = i;
			nearby_systems[ num_nearby_systems ].p_name = sys_info.get<std::string>(std::string(KEY_NAME));
			nearby_systems[ num_nearby_systems ].nova = (UNIVERSE != nullptr ? UNIVERSE->generateSystemData(i) : oo::PList()).get<bool>("sun_gone_nova");
			num_nearby_systems++;
		}
		saved_galaxy_id = (player != nullptr ? player->galaxyNumber() : OOGalaxyID{});
	}
	
	static OOSystemID savedPlanetNumber = 0;
	static OOSystemID savedDestNumber = 0;
	static OORouteType savedArrayMode = OPTIMIZED_BY_NONE;
	static oo::PList routeInfo;	// null: no cached route

	/* May override current mode for mission screens */
	if (backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST || 
		backgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT_ANA_SHORTEST || 
		backgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_SHORTEST)
	{
		advancedNavArrayMode = OPTIMIZED_BY_JUMPS;
	}
	else if (backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST ||
		backgroundSpecial == GUI_BACKGROUND_SPECIAL_SHORT_ANA_QUICKEST ||
		backgroundSpecial == GUI_BACKGROUND_SPECIAL_CUSTOM_ANA_QUICKEST)
	{
		advancedNavArrayMode = OPTIMIZED_BY_TIME;
	}
	
	if (advancedNavArrayMode != OPTIMIZED_BY_NONE && (player != nullptr ? player->hasEquipmentItemProviding("EQ_ADVANCED_NAVIGATIONAL_ARRAY") : false))
	{
		OOSystemID planetNumber = (PLAYER != nullptr ? PLAYER->systemID() : 0);
		OOSystemID destNumber = (PLAYER != nullptr ? PLAYER->targetSystemID() : 0);
		if (routeInfo.isNull() || planetNumber != savedPlanetNumber || destNumber != savedDestNumber || advancedNavArrayMode != savedArrayMode)
		{
			routeInfo = (UNIVERSE != nullptr ? UNIVERSE->routeFromSystem(planetNumber, destNumber, advancedNavArrayMode) : oo::PList());
			savedPlanetNumber = planetNumber;
			savedDestNumber = destNumber;
			savedArrayMode = advancedNavArrayMode;
		}
		target = destNumber;
		
		// if the ANA has been activated and we are in string input mode (i.e. planet search),
		// get out of it so that distance and time data can be displayed
		//if ([[[UNIVERSE gameView] typedString] length] > 0)  [player clearPlanetSearchString];
		
		if (!routeInfo.isNull())  routeExists = YES;
		
		drawAdvancedNavArrayAtX(x+hoffset, y+voffset, z, alpha, (planetNumber != destNumber ? routeInfo : oo::PList()), advancedNavArrayMode, zoom);

		if (routeExists)
		{
			distance = routeInfo.get<double>("distance");
			time = routeInfo.get<double>("time");
			jumps = routeInfo.get<int>("jumps");

			if (distance == 0.0 && planetNumber != destNumber)
			{
				// zero-distance double fix
				distance = 0.1;
				time = 0.01;
			}
		}
	}
	else
	{
		drawAdvancedNavArrayAtX(x+hoffset, y+voffset, z, alpha, oo::PList(), OPTIMIZED_BY_NONE, zoom);
	}
	if (!routeExists)
	{
		NSPoint targetCoordinates = systemManager->getCoordinatesForSystem(target, galaxy_id);

		distance = distanceBetweenPlanetPositions(targetCoordinates.x,targetCoordinates.y,galaxy_coordinates.x,galaxy_coordinates.y);
		if (distance == 0.0)
		{
			if (target != (PLAYER != nullptr ? PLAYER->systemID() : 0))
			{
				// looking at the other half of a zero-distance double
				// distance is treated as 0.1 LY
				distance = 0.1;
			}
		}
		if ((player != nullptr ? player->hasHyperspaceMotor() : false) && distance <= (player != nullptr ? player->getFuel() : OOFuelQuantity{})/10.0)
		{
			time = distance * distance;
		}
		else
		{
			time = 0.0;
		}
	}

	if ((player != nullptr ? player->hasHyperspaceMotor() : false))
	{
		// draw fuel range circle
		OOGL(GLScaledLineWidth(2.0f));
		setGLColorFromSetting(cxx_kGuiChartRangeColor, OOColor::greenColor().get(), alpha);
						
		GLDrawOval(x + cu.x, y + cu.y, z, NSMakeSize((float)(fuel*hscale), 2*(float)(fuel*vscale)), 5);
	}

	
	// draw crosshairs over current location
	//
	setGLColorFromSetting(cxx_kGuiChartCrosshairColor, OOColor::greenColor().get(), alpha);

	drawCrossHairsWithSize(12/zoom+2, x + cu.x, y + cu.y, z);


	// draw crosshairs over cursor
	//
	setGLColorFromSetting(cxx_kGuiChartCursorColor, OOColor::redColor().get(), alpha);
	cu = NSMakePoint((float)(hscale*cursor_coordinates.x+hoffset),(float)(vscale*cursor_coordinates.y+voffset));
	drawCrossHairsWithSize(7/zoom+2, x + cu.x, y + cu.y, z);

	// draw marks and stars
	//
	OOGL(GLScaledLineWidth(1.5f));
	OOGL(glColor4f(1.0f, 1.0f, 0.75f, alpha));	// pale yellow

	for (i = 0; i < num_nearby_systems; i++)
	{
		NSPoint sys_coordinates = systemManager->getCoordinatesForSystem(i, galaxy_id);
		
		dx = fabs(chart_centre_coordinates.x - sys_coordinates.x);
		dy = fabs(chart_centre_coordinates.y - sys_coordinates.y);
	
		if ((dx > zoom*(CHART_WIDTH_AT_MAX_ZOOM/2.0 + CHART_CLIP_BORDER))||(dy > zoom*(CHART_HEIGHT_AT_MAX_ZOOM + CHART_CLIP_BORDER)))
			continue;


		if (concealment[i] >= OO_SYSTEMCONCEALMENT_NOTHING) {
			// system is not known
			continue;
		}

		const oo::PList systemInfo = systemManager->getPropertiesForSystem(i, galaxy_id);
		float blob_factor = guiUserSettings.get<float>(cxx_kGuiChartCircleScale, 0.0017);
		float blob_size = (1.0f + blob_factor * systemInfo.get<float>("radius"))/zoom;
		if (blob_size < 0.5) blob_size = 0.5;

		star.x = (float)(sys_coordinates.x * hscale + hoffset);
		star.y = (float)(sys_coordinates.y * vscale + voffset);

		noNova = !nearby_systems[i].nova;
		OOCAssert(chart_mode <= OOLRC_MODE_TECHLEVEL, "Long range chart mode %i out of range", (int)chart_mode);
	
		if (markedDestinations.has_value())
		{
			const auto markersIt = markedDestinations->find(i);
			if (markersIt != markedDestinations->end())	// is marked
			{
				GLfloat base_size = 0.5f * blob_size + 2.5f;
				drawSystemMarkers(oo::PList(oo::PList::Array(markersIt->second.begin(), markersIt->second.end())), x+star.x, y+star.y, z, alpha, base_size);
			}
		}

		if (concealment[i] >= OO_SYSTEMCONCEALMENT_NODATA) {
			// no system data available
			r = g = b = 0.7;
			OOGL(glColor4f(r, g, b, alpha));
		} else {
			switch (chart_mode)
			{
			case OOLRC_MODE_ECONOMY:
				if (EXPECT(noNova))
				{
					systemParameter = nearby_systems[i].eco;
					GLfloat ce1 = 1.0f - 0.125f * systemParameter;
					setGLColorFromSetting(oo::str::format(cxx_kGuiChartEconomyUColor, systemParameter), OOColor::colorWithRed(ce1, 1.0f, 0.0f, 1.0f).get(), 1.0);
				}
				else
				{
					r = g = b = 0.3;
					OOGL(glColor4f(r, g, b, alpha));
				}
				break;
			case OOLRC_MODE_GOVERNMENT:
				if (EXPECT(noNova))
				{
					systemParameter = nearby_systems[i].gov;
					setGLColorFromSetting(oo::str::format(cxx_kGuiChartGovernmentUColor, systemParameter), OOColor::colorWithRed(govcol[systemParameter*3], govcol[1+(systemParameter*3)], govcol[2+(systemParameter*3)], 1.0f).get(), 1.0);
				}
				else
				{
					r = g = b = 0.3;
					OOGL(glColor4f(r, g, b, alpha));
				}
				break;
			case OOLRC_MODE_TECHLEVEL:
				if (EXPECT(noNova))
				{
					systemParameter = nearby_systems[i].tec;
					r = 0.6;
					g = b = 0.20 + (0.05 * (GLfloat)systemParameter);
				}
				else
				{
					r = g = b = 0.3;
				}			
				OOGL(glColor4f(r, g, b, alpha));
				break;
			case OOLRC_MODE_UNKNOWN:
			case OOLRC_MODE_SUNCOLOR:
				if (EXPECT(noNova))
				{
					r = g = b = 1.0;
					oo::Ref<OOColor>	sunColor = OOColor::colorWithDescription(((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getProperty("sun_color", i, galaxy_id) : oo::PList()));
					if (sunColor != nil) {
						sunColor->getRed(&r, &g, &b, &alpha);
						alpha = 1.0; // reset
					}
				}
				else
				{
					r = 1.0;
					g = 0.2;
					b = 0.0;
				}
				OOGL(glColor4f(r, g, b, alpha));
				break;
			}
		}
		
		GLDrawFilledOval(x + star.x, y + star.y, z, NSMakeSize(blob_size,blob_size), 15);
	}
	
	// draw found stars and captions
	//
	GLfloat systemNameScale = guiUserSettings.get<float>(cxx_kGuiChartLabelScale, 1.0);

	OOGL(GLScaledLineWidth(1.5f));
	setGLColorFromSetting(cxx_kGuiChartMatchBoxColor, OOColor::greenColor().get(), alpha);

	int n_matches = 0, foundIndex = -1;
	
	for (i = 0; i < 256; i++) if (systemsFound[i])
	{
		if(foundSystem == n_matches) foundIndex = i;
		n_matches++;
	}
	
	if (n_matches == 0)
	{
		foundSystem = 0;
	}
	else if (backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST || backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST || backgroundSpecial == GUI_BACKGROUND_SPECIAL_LONG)
	{
		// do nothing at this stage
	}
	else
	{
		for (i = 0; i < 256; i++)
		{
			if (concealment[i] >= OO_SYSTEMCONCEALMENT_NONAME)
			{
				continue;
			}
			
			BOOL mark = systemsFound[i];
			float marker_size = 8.0/zoom;
			NSPoint sys_coordinates = systemManager->getCoordinatesForSystem(i, galaxy_id);

			dx = fabs(chart_centre_coordinates.x - sys_coordinates.x);
			dy = fabs(chart_centre_coordinates.y - sys_coordinates.y);
		
			if (mark && (dx <= zoom*(CHART_WIDTH_AT_MAX_ZOOM/2.0+CHART_CLIP_BORDER))&&(dy <= zoom*(CHART_HEIGHT_AT_MAX_ZOOM+CHART_CLIP_BORDER)))
			{
				star.x = (float)(sys_coordinates.x * hscale + hoffset);
				star.y = (float)(sys_coordinates.y * vscale + voffset);
				OOGLBEGIN(GL_LINE_LOOP);
					glVertex3f(x + star.x - marker_size,	y + star.y - marker_size,	z);
					glVertex3f(x + star.x + marker_size,	y + star.y - marker_size,	z);
					glVertex3f(x + star.x + marker_size,	y + star.y + marker_size,	z);
					glVertex3f(x + star.x - marker_size,	y + star.y + marker_size,	z);
				OOGLEND();
				if (i == foundIndex || n_matches == 1)
				{
					if (n_matches == 1) foundSystem = 0;
					if (zoom > CHART_ZOOM_SHOW_LABELS && advancedNavArrayMode == OPTIMIZED_BY_NONE)
					{
						setGLColorFromSetting(cxx_kGuiChartMatchLabelColor, OOColor::cyanColor().get(), alpha);
						cxx_OODrawString((UNIVERSE != nullptr ? UNIVERSE->systemNameIndex(i) : std::optional<std::string>()).value_or("") , x + star.x + 2.0, y + star.y - 10.0f, z, NSMakeSize(10*systemNameScale,10*systemNameScale));
						setGLColorFromSetting(cxx_kGuiChartMatchBoxColor, OOColor::greenColor().get(), alpha);
					}
				}
				else if (zoom > CHART_ZOOM_SHOW_LABELS)
				{
					cxx_OODrawString((UNIVERSE != nullptr ? UNIVERSE->systemNameIndex(i) : std::optional<std::string>()).value_or("") , x + star.x + 2.0, y + star.y - 10.0f, z, NSMakeSize(10*systemNameScale,10*systemNameScale));
				}
			}
		}
	}

	// draw names
	//
//	OOGL(glColor4f(1.0f, 1.0f, 0.0f, alpha));	// yellow
	
	int targetIdx = -1;
	struct saved_system *sys;
	NSSize chSize = NSMakeSize(pixel_row_height*systemNameScale/zoom,pixel_row_height*systemNameScale/zoom);
	
	double jumpRange = MAX_JUMP_RANGE * (PLAYER != nullptr ? PLAYER->dialFuel() : 0.0f);
	for (i = 0; i < num_nearby_systems; i++)
	{
		if (concealment[i] >= OO_SYSTEMCONCEALMENT_NONAME)
		{
			continue;
		}

		sys = nearby_systems + i;
		NSPoint sys_coordinates = systemManager->getCoordinatesForSystem(sys->sysid, galaxy_id);

		dx = fabs(chart_centre_coordinates.x - sys_coordinates.x);
		dy = fabs(chart_centre_coordinates.y - sys_coordinates.y);
		
		if ((dx > zoom*(CHART_WIDTH_AT_MAX_ZOOM/2.0+CHART_CLIP_BORDER))||(dy > zoom*(CHART_HEIGHT_AT_MAX_ZOOM+CHART_CLIP_BORDER)))
			continue;
		star.x = (float)(sys_coordinates.x * hscale + hoffset);
		star.y = (float)(sys_coordinates.y * vscale + voffset);
		if (sys->sysid == target)		// not overlapping twin? (example: Divees & Tezabi in galaxy 5)
		{
			 targetIdx = i;		// we have a winner!
		}


		
		if (zoom < CHART_ZOOM_SHOW_LABELS)
		{
			if (!(player != nullptr ? player->showInfoFlag() : false))	// System's name
			{

				d = distanceBetweenPlanetPositions(galaxy_coordinates.x, galaxy_coordinates.y, sys_coordinates.x, sys_coordinates.y);
				if (d <= jumpRange)
				{
					setGLColorFromSetting(cxx_kGuiChartLabelReachableColor, OOColor::yellowColor().get(), alpha);
				}
				else
				{
					setGLColorFromSetting(cxx_kGuiChartLabelColor, OOColor::yellowColor().get(), alpha);

				}

				cxx_OODrawString(sys->p_name, x + star.x + 2.0, y + star.y, z, chSize);
			}
			else if (EXPECT(sys->gov >= 0))	// Not a nova? Show the info.
			{
				if (concealment[i] >= OO_SYSTEMCONCEALMENT_NODATA)
				{
					setGLColorFromSetting(cxx_kGuiChartLabelColor, OOColor::yellowColor().get(), alpha);
					cxx_OODrawHilightedString("???", x + star.x + 2.0, y + star.y, z, chSize);
				}
				else
				{
					OODrawPlanetInfo(sys->gov, sys->eco, sys->tec, x + star.x + 2.0, y + star.y + 2.0, z, chSize);
				}
			}
		}
	}
	
	// highlight the name of the currently selected system
	// (needed to get things right in closely-overlapping systems)
	if( targetIdx != -1 && zoom <= CHART_ZOOM_SHOW_LABELS)
	{
		if (concealment[targetIdx] < OO_SYSTEMCONCEALMENT_NONAME)
		{
			sys = nearby_systems + targetIdx;
			NSPoint sys_coordinates = systemManager->getCoordinatesForSystem(sys->sysid, galaxy_id);

			star.x = (float)(sys_coordinates.x * hscale + hoffset);
			star.y = (float)(sys_coordinates.y * vscale + voffset);
		
			if (!(player != nullptr ? player->showInfoFlag() : false))
			{
				d = distanceBetweenPlanetPositions(galaxy_coordinates.x, galaxy_coordinates.y, sys_coordinates.x, sys_coordinates.y);
				if (d <= jumpRange)
				{
					setGLColorFromSetting(cxx_kGuiChartLabelReachableColor, OOColor::yellowColor().get(), alpha);
				}
				else
				{
					setGLColorFromSetting(cxx_kGuiChartLabelColor, OOColor::yellowColor().get(), alpha);
				
				}

				cxx_OODrawHilightedString(sys->p_name, x + star.x + 2.0, y + star.y, z, chSize);
			}
			else if (sys->gov >= 0)	// Not a nova? Show the info.
			{
				if (concealment[targetIdx] >= OO_SYSTEMCONCEALMENT_NODATA)
				{
					setGLColorFromSetting(cxx_kGuiChartLabelColor, OOColor::yellowColor().get(), alpha);
					cxx_OODrawHilightedString("???", x + star.x + 2.0, y + star.y, z, chSize);
				}
				else
				{
					OODrawHilightedPlanetInfo(sys->gov, sys->eco, sys->tec, x + star.x + 2.0, y + star.y + 2.0, z, chSize);
				}
			}
		}
	}
	
	OOGUITabSettings tab_stops;
	tab_stops[0] = 0;
	tab_stops[1] = 96;
	tab_stops[2] = 288;
	overrideTabs(tab_stops, cxx_kGuiChartTraveltimeTabs, 3);
	setTabStops(tab_stops);
	const std::string targetName = (UNIVERSE != nullptr ? UNIVERSE->getSystemName(target) : std::optional<std::string>()).value_or(std::string());

	// distance-f & est-travel-time-f are identical between short & long range charts in standard Oolite, however can be alterered separately via OXPs
	std::string travelDistLine;
	if (distance > 0)
	{
		travelDistLine = cxx_OOExpandKey("long-range-chart-distance", distance).value_or(std::string());
	}
	std::string travelTimeLine;
	if (time > 0)
	{
		travelTimeLine = cxx_OOExpandKey("long-range-chart-est-travel-time", time).value_or(std::string());
	}
	
	if(concealment[target] < OO_SYSTEMCONCEALMENT_NONAME)
	{
		setArray({ targetName, travelDistLine, travelTimeLine }, textRow);
	}
	else
	{
		setArray({ "", travelDistLine, travelTimeLine }, textRow);
	}
	if ((PLAYER != nullptr ? PLAYER->guiScreen() : OOGUIScreenID{}) == GUI_SCREEN_SHORT_RANGE_CHART)
	{
		if (jumps > 0)
		{
			setArray({ "", cxx_OOExpandKey("short-range-chart-jumps", jumps).value_or(std::string()) }, textRow + 1);
		}
		else
		{
			setArray({}, textRow + 1);
		}
	}

	// draw planet info circle
	OOGL(GLScaledLineWidth(2.0f));
	setGLColorFromSetting(cxx_kGuiChartInfoMarkerColor, OOColor::blueColor().get(), alpha);
	cu = NSMakePoint((float)(hscale*info_system_coordinates.x+hoffset),(float)(vscale*info_system_coordinates.y+voffset));
	GLDrawOval(x + cu.x, y + cu.y, z, NSMakeSize(6.0f/zoom+2.0f, 6.0f/zoom+2.0f), 5);

	// disable draw clipping
	OOGL(glDisable(GL_SCISSOR_TEST));

	// Draw bottom divider
	setGLColorFromSetting(cxx_kGuiScreenDividerColor, OOColor::colorWithWhite(0.75, 1.0).get(), alpha);
	OOGLBEGIN(GL_QUADS);
		glVertex3f(x + 0, (float)(y + size_in_pixels.height - (textRow-1)*MAIN_GUI_ROW_HEIGHT - pixel_title_size.height),	z);
		glVertex3f(x + size_in_pixels.width, (GLfloat)(y + size_in_pixels.height - (textRow-1)*MAIN_GUI_ROW_HEIGHT - pixel_title_size.height), z);
		glVertex3f(x + size_in_pixels.width, (GLfloat)(y + size_in_pixels.height - (textRow-1)*MAIN_GUI_ROW_HEIGHT - pixel_title_size.height - 2), z);
		glVertex3f(x + 0, (GLfloat)(y + size_in_pixels.height - (textRow-1)*MAIN_GUI_ROW_HEIGHT - pixel_title_size.height - 2), z);
	OOGLEND();
}


// One-line bridge (amendment oo-9ht.139 item 3), moved from the GUI's deleted facade (bead oo-9ht.143).
bool GuiDisplayGenUniverseUseShaders()
{
	return (UNIVERSE != nullptr ? UNIVERSE->useShaders() : false);
}
