    - (void) undo:(id)sender
    {
        [self sendEditMenuCommand:EDIT_COMMAND_UNDO];
    }

    - (void) miniaturize:(id)sender
    {
        /* When Stage Manager is enabled, miniaturize: just moves the app/window to
         * the background rather than minimizing the window.
         * Don't start minimizing the window on the Win32 side.
         */
        if (stage_manager_enabled())
        {
            [super miniaturize:sender];
            return;
        }

        macdrv_event* event = macdrv_create_event(WINDOW_MINIMIZE_REQUESTED, self);
        [queue postEvent:event];
        macdrv_release_event(event);

        WineWindow* parent = (WineWindow*)self.parentWindow;
        if ([parent isKindOfClass:[WineWindow class]])
            [parent grabDockIconSnapshotFromWindow:self force:YES];
    }

