static BOOL context_sync_drawables( struct wgl_context *context, HDC draw_hdc, HDC read_hdc )
{
    struct opengl_drawable *new_draw, *new_read, *old_draw = NULL, *old_read = NULL;
    struct wgl_context *previous = NtCurrentTeb()->glContext;
    BOOL ret = FALSE;

    if (!(new_draw = get_updated_drawable( draw_hdc, context->format, context->draw ))) return FALSE;
    if (!draw_hdc && context->draw == context->read) opengl_drawable_add_ref( (new_read = new_draw) );
    else if (draw_hdc && draw_hdc == read_hdc) opengl_drawable_add_ref( (new_read = new_draw) );
    else new_read = get_updated_drawable( read_hdc, context->format, context->read );

    TRACE( "context %p, new_draw %s, new_read %s\n", context, debugstr_opengl_drawable( new_draw ), debugstr_opengl_drawable( new_read ) );

    if (!new_draw || !new_read)
    {
        WARN( "One of the drawable has been lost, ignoring\n" );
        return FALSE;
    }

    if (previous == context && new_draw == context->draw && new_read == context->read) ret = TRUE;
    else if (previous)
    {
        context_exchange_drawables( previous, &old_draw, &old_read ); /* take ownership of the previous context drawables */
        opengl_drawable_set_context( old_read, NULL );
        if (old_read != old_draw) opengl_drawable_set_context( old_draw, NULL );
    }

    if (!ret && (ret = driver_funcs->p_make_current( new_draw, new_read, context->driver_private )))
    {
        NtCurrentTeb()->glContext = context;

        if (old_draw && old_draw != new_draw && old_draw != new_read && old_draw->client)
            set_window_opengl_drawable( old_draw->client->hwnd, old_draw, FALSE );
        if (old_read && old_read != new_draw && old_read != new_read && old_read->client)
            set_window_opengl_drawable( old_read->client->hwnd, old_read, FALSE );

        /* all good, release previous context drawables if any */
        if (old_draw) opengl_drawable_release( old_draw );
        if (old_read) opengl_drawable_release( old_read );

        opengl_drawable_set_context( new_read, context );
        if (new_read != new_draw) opengl_drawable_set_context( new_draw, context );

        opengl_drawable_flush( new_read, new_read->interval, 0 );
        opengl_drawable_flush( new_draw, new_draw->interval, GL_FLUSH_PRESENT );
    }

    if (ret)
    {
        /* update the current window drawable to the last used draw surface */
        if (new_draw->client) set_window_opengl_drawable( new_draw->client->hwnd, new_draw, TRUE );
        context_exchange_drawables( context, &new_draw, &new_read );
    }
    else if (previous)
    {
        opengl_drawable_set_context( old_read, context );
        if (old_read != old_draw) opengl_drawable_set_context( old_draw, context );
        context_exchange_drawables( previous, &old_draw, &old_read ); /* give back ownership of the previous drawables */
        assert( !old_draw && !old_read );
    }

    if (new_draw) opengl_drawable_release( new_draw );
    if (new_read) opengl_drawable_release( new_read );
    return ret;
}
