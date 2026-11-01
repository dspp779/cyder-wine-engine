/* Wine source excerpts; #line preserves coordinates for patch reconstruction. */
#line 1
/*
 * Mac driver OpenGL support
 *
 * Copyright 2012 Alexandre Julliard
 * Copyright 2012, 2013 Ken Thomases for CodeWeavers Inc.
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

#if 0
#pragma makedep unix
#endif

#include "config.h"
/* Test excerpts: omitted lines stay blank to retain original patch coordinates. */




#include "winnt.h"
#include "wine/debug.h"
#include "wine/opengl_driver.h"

#define GL_SILENCE_DEPRECATION
#define __gl_h_


#line 69


    macdrv_view             read_view;
    CGLPBufferObj           read_pbuffer;
    int                     swap_interval;
};

struct gl_drawable


#line 1451


        return FALSE;
    }
    context->swap_interval = INT_MIN;

    TRACE("created context %p/%p/%p\n", context, context->context, context->cglcontext);


#line 2013


static void macdrv_surface_flush(struct opengl_drawable *base, UINT flags)
{
    struct macdrv_client_surface *client = impl_from_client_surface(base->client);
    struct macdrv_context *context = NtCurrentTeb()->glReserved2;

    TRACE("%s flags %#x\n", debugstr_opengl_drawable(base), flags);

    if (!context) return;
    if (flags & GL_FLUSH_INTERVAL) set_swap_interval(context, base->interval);
    if ((flags & GL_FLUSH_UPDATED) || macdrv_opengl_context_backing_sync_pending(context->context))
        make_context_current(context, context->read_view == client->cocoa_view);
    if (flags & GL_FLUSH_PRESENT)
    {
        macdrv_flush_opengl_context(context->context);
        client_surface_present(base->client);
    }
}


#line 2848


    TRACE("deleting context %p/%p/%p\n", context, context->context, context->cglcontext);

    macdrv_dispose_opengl_context(context->context);
    free(context);
    return TRUE;


#line 2870


static BOOL macdrv_surface_swap(struct opengl_drawable *base)
{
    struct macdrv_context *context = NtCurrentTeb()->glReserved2;

    TRACE("%s context %p/%p/%p\n", debugstr_opengl_drawable(base), context, (context ? context->context : NULL),
          (context ? context->cglcontext : NULL));

    if (context)
    {
        if (macdrv_opengl_context_backing_sync_pending(context->context))
            make_context_current(context, FALSE);
        macdrv_flush_opengl_context(context->context);
    }
    client_surface_present(base->client);
    return TRUE;
}

static const struct opengl_driver_funcs macdrv_driver_funcs =


