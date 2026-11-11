/*
 * MACDRV Cocoa window code
 *
 * Copyright 2011, 2012, 2013 Ken Thomases for CodeWeavers Inc.
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

    - (void) addGLContext:(WineOpenGLContext*)context
    {
        BOOL hadContext = _everHadGLContext;
        if (!glContexts)
            glContexts = [[NSMutableArray alloc] init];
        if (!pendingGlContexts)
            pendingGlContexts = [[NSMutableArray alloc] init];

        if ([[self window] windowNumber] > 0 && !NSIsEmptyRect([self visibleRect]))
        {
            [glContexts addObject:context];
            context.needsUpdate = TRUE;
        }
        else
        {
            [pendingGlContexts addObject:context];
            [self setNeedsDisplay:YES];
        }

        _everHadGLContext = YES;
        if (!hadContext)
            [self invalidateHasGLDescendant];
        [(WineWindow*)[self window] updateForGLSubviews];
    }
