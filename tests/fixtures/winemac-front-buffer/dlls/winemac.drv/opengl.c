static void macdrv_surface_flush(struct opengl_drawable *base, UINT flags)
{
    struct macdrv_client_surface *client = impl_from_client_surface(base->client);
    struct macdrv_context *context = NtCurrentTeb()->glReserved2;

    TRACE("%s flags %#x\n", debugstr_opengl_drawable(base), flags);

    if (!context) return;
    if (flags & GL_FLUSH_INTERVAL) set_swap_interval(context, base->interval);
    if ((flags & GL_FLUSH_UPDATED) || macdrv_opengl_context_backing_sync_pending(context->context))
        make_context_current(context, context->read_view == client->cocoa_view);
}


static BOOL macdrv_surface_swap(struct opengl_drawable *base)
{
    struct macdrv_context *context = NtCurrentTeb()->glReserved2;

    TRACE("%s context %p/%p/%p\n", debugstr_opengl_drawable(base), context, (context ? context->context : NULL),
          (context ? context->cglcontext : NULL));

    if (macdrv_opengl_context_backing_sync_pending(context->context))
        make_context_current(context, FALSE);
    macdrv_flush_opengl_context(context->context);
    return TRUE;
}


