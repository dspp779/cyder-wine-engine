    static NSComparisonResult compare_windows_back_to_front(NSWindow* window1, NSWindow* window2, NSArray* windowNumbers)
    {
        NSNumber* window1Number = [NSNumber numberWithInteger:[window1 windowNumber]];
        NSNumber* window2Number = [NSNumber numberWithInteger:[window2 windowNumber]];
        NSUInteger index1 = [windowNumbers indexOfObject:window1Number];
        NSUInteger index2 = [windowNumbers indexOfObject:window2Number];
        if (index1 == NSNotFound)
        {
            if (index2 == NSNotFound)
                return NSOrderedSame;
            else
                return NSOrderedAscending;
        }
        else if (index2 == NSNotFound)
            return NSOrderedDescending;
        else if (index1 < index2)
            return NSOrderedDescending;
        else if (index2 < index1)
            return NSOrderedAscending;

        return NSOrderedSame;
    }

    - (void) order:(NSWindowOrderingMode)mode childWindow:(WineWindow*)child relativeTo:(WineWindow*)other
    {
        NSMutableArray* windowNumbers;
        NSNumber* childWindowNumber;
        NSUInteger otherIndex;
        NSArray* origChildren;
        NSMutableArray* children;

        // Get the z-order from the window server and modify it to reflect the
        // requested window ordering.
        windowNumbers = [[[[self class] windowNumbersWithOptions:NSWindowNumberListAllSpaces] mutableCopy] autorelease];
        childWindowNumber = [NSNumber numberWithInteger:[child windowNumber]];
        [windowNumbers removeObject:childWindowNumber];
        if (other)
        {
            otherIndex = [windowNumbers indexOfObject:[NSNumber numberWithInteger:[other windowNumber]]];
            [windowNumbers insertObject:childWindowNumber atIndex:otherIndex + (mode == NSWindowAbove ? 0 : 1)];
        }
        else if (mode == NSWindowAbove)
            [windowNumbers insertObject:childWindowNumber atIndex:0];
        else
            [windowNumbers addObject:childWindowNumber];

        // Get our child windows and sort them in the reverse of the desired
        // z-order (back-to-front).
        origChildren = [self childWineWindows];
        children = [[origChildren mutableCopy] autorelease];
        [children sortWithOptions:NSSortStable
                  usingComparator:^NSComparisonResult(id obj1, id obj2){
            return compare_windows_back_to_front(obj1, obj2, windowNumbers);
        }];

        [self setChildWineWindows:children];
    }
