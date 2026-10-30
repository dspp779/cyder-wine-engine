static void opengl_drawable_flush( struct opengl_drawable *drawable, int interval, UINT flags )
{
    if (!is_client_surface_window( drawable->client, 0 )) return;

    if (InterlockedCompareExchange( &drawable->client->updated, 0, 1 )) flags |= GL_FLUSH_UPDATED;
    if (interval != drawable->interval)
    {
        drawable->interval = interval;
        flags = GL_FLUSH_INTERVAL;
    }

    if (flags) drawable->funcs->flush( drawable, flags );
}
