/*
 Copyright 2011 repetier repetierdev@googlemail.com
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "STLComposer.h"
#import "STL.h"
#import "RHAppDelegate.h"
#import "RHAnimation.h"
#import "PrinterConfiguration.h"
#import "PrinterConnection.h"
#import "ThreeDContainer.h"
#import "RHOpenGLView.h"
#import "Slicer.h"
#import "RHLogger.h"

STLComposer *stlComposer=nil;

@implementation STLComposer

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        if ([NSBundle loadNibNamed:@"STLComposer" owner:self])
        {
            files = [RHLinkedList new];
            [view setFrame:[self bounds]];
            [self addSubview:view];
            [[NSNotificationCenter defaultCenter] addObserver:self                                             selector:@selector(objectSelected:) name:@"RHObjectSelected" object:nil];
            [[NSNotificationCenter defaultCenter] addObserver:self                                             selector:@selector(objectMoved:) name:@"RHObjectMoved" object:nil];
            [self updateView];
            openPanel = [[NSOpenPanel openPanel] retain];
            [openPanel setCanChooseDirectories:YES];
            [openPanel setAllowsMultipleSelection:NO];
            [view registerForDraggedTypes:[NSArray arrayWithObjects:
                                           NSURLPboardType, NSFilenamesPboardType, nil]];
        }
    }
    stlComposer = self;
    return self;
}
-(void)dealloc {
    [files release];
    [openPanel release];
    [super dealloc];
}
- (void)drawRect:(NSRect)dirtyRect
{
    // Drawing code here.
}

-(void)objectSelected:(NSNotification*)obj {
    int idx = 0;
    for(STL *stl in files) {
        if(obj.object==stl) {
            NSUInteger mod = [NSEvent modifierFlags];
            NSIndexSet *set = [NSIndexSet indexSetWithIndex:idx];
            if(mod==NSCommandKeyMask)
                [filesTable selectRowIndexes:set byExtendingSelection:mod==NSCommandKeyMask];
            else if(mod==NSControlKeyMask) {
                if(stl->selected)
                    [filesTable deselectRow:idx];
                else
                    [filesTable selectRowIndexes:set byExtendingSelection:YES];
            } else
                [filesTable selectRowIndexes:set byExtendingSelection:NO];
                
            [self updateView];
        }
        idx++;
    }
}
-(void)updateView {
    NSIndexSet *set = [filesTable selectedRowIndexes];
    NSInteger idx = [filesTable selectedRow];
    int cnt = (int)set.count;
    if(cnt!=1) { // Deselected
        [removeSTLfileButton setEnabled:cnt>0];
        [dropObjectButton setEnabled:cnt>0];
        [centerObjectButton setEnabled:NO];
        [translationX setEnabled:NO];
        [translationY setEnabled:NO];
        [translationZ setEnabled:NO];
        [scaleX setEnabled:NO];
        [scaleY setEnabled:NO];
        [scaleZ setEnabled:NO];
        [lockAspect setEnabled:NO];
        [rotateX setEnabled:NO];
        [rotateY setEnabled:NO];
        [rotateZ setEnabled:NO];
        actSTL = idx<0 ? nil : [files objectAtIndex:(int)idx];
        int i=0;
        for(STL *stl in files) { 
            stl->selected = [set containsIndex:i];
            i++;
        }
    } else {
        [removeSTLfileButton setEnabled:YES];
        [dropObjectButton setEnabled:YES];
        [centerObjectButton setEnabled:YES];
        [translationX setEnabled:YES];
        [translationY setEnabled:YES];
        [translationZ setEnabled:YES];
        [scaleX setEnabled:YES];
        [scaleY setEnabled:YES];
        [scaleZ setEnabled:YES];
        [lockAspect setEnabled:YES];
        [rotateX setEnabled:YES];
        [rotateY setEnabled:YES];
        [rotateZ setEnabled:YES];
        int p=0;
        for(STL *stl in files) { 
            stl->selected = idx==p;
            if(stl->selected)
                actSTL = stl;
            p++;
        }
        [translationX setDoubleValue:actSTL->position[0]];
        [translationY setDoubleValue:actSTL->position[1]];
        [translationZ setDoubleValue:actSTL->position[2]];
        [scaleX setDoubleValue:actSTL->scale[0]];
        [scaleY setDoubleValue:actSTL->scale[1]];
        [scaleZ setDoubleValue:actSTL->scale[2]];
        [rotateX setDoubleValue:actSTL->rotation[0]];
        [rotateY setDoubleValue:actSTL->rotation[1]];
        [rotateZ setDoubleValue:actSTL->rotation[2]];
        if(actSTL->scale[0] == actSTL->scale[1] && actSTL->scale[0] == actSTL->scale[2]) {
            [lockAspect setState:1];
            [scaleY setEnabled:NO];
            [scaleZ setEnabled:NO];
        } else {
            [lockAspect setState:0];
            [scaleY setEnabled:YES];
            [scaleZ setEnabled:YES];
        }
    }
    if(app!=nil && app->openGLView!=nil)
        [app->openGLView redraw];
}
// TextField like Translation, Scale or Rotate changed
- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
    if(actSTL==nil) return;
    actSTL->position[0] = translationX.doubleValue;
    actSTL->position[1] = translationY.doubleValue;
    actSTL->position[2] = translationZ.doubleValue;
    actSTL->scale[0] = scaleX.doubleValue;
    if(lockAspect.state) {
        [scaleY setDoubleValue:scaleX.doubleValue];
        [scaleZ setDoubleValue:scaleX.doubleValue];
    }
    actSTL->scale[1] = scaleY.doubleValue;
    actSTL->scale[2] = scaleZ.doubleValue;
    actSTL->rotation[0] = rotateX.doubleValue;
    actSTL->rotation[1] = rotateY.doubleValue;
    actSTL->rotation[2] = rotateZ.doubleValue;
    [app->openGLView redraw];
}
- (IBAction)saveAsSTL:(NSButton *)sender {
    [openPanel setMessage:@"Save STL file"];
    [openPanel beginSheetModalForWindow:app->mainWindow completionHandler:^(NSInteger result){
        if (result == NSFileHandlingPanelOKButton) {
            NSArray* urls = [openPanel URLs];
            if(urls.count>0) {
                [self saveSTLToFile:[[urls objectAtIndex:0] path]];
            }
        }        
    }];
}

- (IBAction)generateGCode:(NSButton *)sender {
    NSString *file = @"~/Library/Repetier/tempobj.stl";
    file = [file stringByExpandingTildeInPath];
    [self saveSTLToFile:file];
    [app->slicer slice:file];
}

- (IBAction)centerObject:(NSButton *)sender {
    if(actSTL==nil) return;
    [actSTL centerX:currentPrinterConfiguration->width/2 y:currentPrinterConfiguration->depth/2];
    [app->openGLView redraw];
    [self updateView];
}

- (IBAction)dropObject:(NSButton *)sender {
    for(STL *act in files) {
        if(act->selected)
            [act land];
    }
    [app->openGLView redraw];
    [self updateView];
}
-(void)normalize:(float*)n
{
    float d = (float)sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
    n[0] /= d;
    n[1] /= d;
    n[2] /= d;
}

-(void)saveSTLToFile:(NSString*)file {
    int32_t n = 0;
    for (STL *stl in files)
        n += stl->list->count;
    NSMutableArray *triList = [[NSMutableArray alloc] initWithCapacity:n];
    for(STL *stl in files)
    {
        [stl updateMatrix];
        for(STLTriangle *t2 in stl->list)
        {
            STLTriangle *t = [STLTriangle new];
            [stl transformPoint:t2->p1 to:t->p1];
            [stl transformPoint:t2->p2 to:t->p2];
            [stl transformPoint:t2->p3 to:t->p3];
            // Compute normal from p1-p3
            float ax = t->p2[0] - t->p1[0];
            float ay = t->p2[1] - t->p1[1];
            float az = t->p2[2] - t->p1[2];
            float bx = t->p3[0] - t->p1[0];
            float by = t->p3[1] - t->p1[1];
            float bz = t->p3[2] - t->p1[2];
            t->normal[0] = ay * bz - az * by;
            t->normal[1] = az * bx - ax * bz;
            t->normal[2] = ax * by - ay * bx;
            [self normalize:t->normal];
            [triList addObject:t];
        }
    }
    // STL should have increasing z for faster slicing
    [triList sortUsingSelector:@selector(compare:)];
    // Write file in binary STL format
    FILE *f=fopen([file UTF8String],"w");    
    int i,zero=0;
    for (i = 0; i < 20; i++) fwrite(&zero,4,1,f);
    fwrite(&n,4,1,f);
    for (STLTriangle *t in triList)
    {
        fwrite(t->normal,sizeof(float)*3,1,f);
        fwrite(t->p1,sizeof(float)*3,1,f);
        fwrite(t->p2,sizeof(float)*3,1,f);
        fwrite(t->p3,sizeof(float)*3,1,f);
        fwrite(&zero,2,1,f);
    }
    fclose(f); 
}
-(void)loadSTLFile:(NSString*)fname {
    STL *stl = [STL new];
    if([stl load:fname]) {
        [app->rightTabView selectTabViewItem:app->composerTab];
        [app->leftTabView selectTabViewItem:app->threedViewTabItem];
        [stl centerX:currentPrinterConfiguration->width/2 y:currentPrinterConfiguration->depth/2];
        [app->stlView->models addLast:stl];     
        DropAnimation *panim = [[DropAnimation alloc] initDropAnimation:@"drop"];
        [stl addAnimation:panim];
        [files addLast:stl];
        [panim release];
        [filesTable reloadData];
        [app->stlHistory add:fname];
    } else {
        [rhlog addError:@"Couldn't import STL file. Invalid format?"];
    }
    [stl release];
    
}
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    NSPasteboard *pboard;
    NSDragOperation sourceDragMask;
    
    sourceDragMask = [sender draggingSourceOperationMask];
    pboard = [sender draggingPasteboard];
    
    if ( [[pboard types] containsObject:NSURLPboardType] ) {
        if (sourceDragMask & NSDragOperationCopy) {
            return NSDragOperationGeneric;
        }
    }
    if ( [[pboard types] containsObject:NSFilenamesPboardType] ) {
        if (sourceDragMask & NSDragOperationLink) {
            return NSDragOperationLink;
        } else if (sourceDragMask & NSDragOperationCopy) {
            return NSDragOperationCopy;
        }
    }
    return NSDragOperationNone;
}
- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];
    
    if ( [[pboard types] containsObject:NSURLPboardType] ) {
        NSURL *fileURL = [NSURL URLFromPasteboard:pboard];
        [self loadSTLFile:fileURL.path];
    }
    return YES;
}
- (IBAction)addSTLFile:(NSButton *)sender {
    [openPanel setMessage:@"Load STL file"];
    [openPanel beginSheetModalForWindow:app->mainWindow completionHandler:^(NSInteger result){
        if (result == NSFileHandlingPanelOKButton) {
            NSArray* urls = [openPanel URLs];
            if(urls.count>0) {
                [self loadSTLFile:[[urls objectAtIndex:0] path]];
            }
        }        
    }];
}

- (IBAction)removeSTLFile:(id)sender {
    if(actSTL==nil)return;
    BOOL found = NO;
    do {
        found = NO;
        for(STL *act in files) {
            if(act->selected==NO) continue;
            [files remove:act];
            [app->stlView->models remove:act];
            found=YES;
            break;
        }
    } while(found);
    [filesTable reloadData];
    actSTL=nil;
    [self updateView];
    [app->openGLView redraw];
}

- (IBAction)changeLockAspect:(NSButton *)sender {
    if(lockAspect.state) {
        [scaleY setEnabled:NO];
        [scaleZ setEnabled:NO];
    } else {
        [scaleY setEnabled:YES];
        [scaleZ setEnabled:YES];
    }
    [self controlTextDidEndEditing:nil];
}
-(void)objectMoved:(NSNotification*)obj {
    RHPoint *p = obj.object;
    if([app->rightTabView selectedTabViewItem]!=app->composerTab) return;
    for(STL *act in files) {
        if(!act->selected) continue;
        act->position[0]+=p->x;
        act->position[1]+=p->y;
    }
    [app->openGLView redraw];
    [self updateView];
}
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
    [self updateView];
}
// NSTableViewDelegates
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return files->count;
}
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    return ((STL*)[files objectAtIndex:(int)rowIndex])->name;
}
@end