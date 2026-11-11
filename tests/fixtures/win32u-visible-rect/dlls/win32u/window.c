/*
 * Window related functions
 *
 * Copyright 1993, 1994 Alexandre Julliard
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA
 */

static RECT get_visible_rect( HWND hwnd, BOOL shaped, UINT style, UINT ex_style, const struct window_rects *rects )
{
    UINT dpi = get_dpi_for_window( hwnd ), style_mask, ex_style_mask;
    RECT visible_rect, rect = {0};

    if (get_present_rect( hwnd, &rect, get_thread_dpi() )) return rect;
    if (IsRectEmpty( &rects->window ) || EqualRect( &rects->window, &rects->client ) || shaped || !decorated_mode) return rects->window;
    if (!user_driver->pGetWindowStyleMasks( hwnd, style, ex_style, &style_mask, &ex_style_mask )) return rects->window;
    if (!NtUserAdjustWindowRect( &rect, style & style_mask, FALSE, ex_style & ex_style_mask, dpi )) return rects->window;

    visible_rect = rects->window;
    visible_rect.left   -= rect.left;
    visible_rect.right  -= rect.right;
    visible_rect.top    -= rect.top;
    visible_rect.bottom -= rect.bottom;
    if (visible_rect.top >= visible_rect.bottom) visible_rect.bottom = visible_rect.top + 1;
    if (visible_rect.left >= visible_rect.right) visible_rect.right = visible_rect.left + 1;

    TRACE( "hwnd %p, rects %s, style %#x, ex_style %#x -> visible_rect %s\n", hwnd,
           debugstr_window_rects( rects ), style, ex_style, wine_dbgstr_rect( &visible_rect ) );
    return visible_rect;
}

