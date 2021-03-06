/*
 *  BillboardManager.mm
 *  WhirlyGlobeLib
 *
 *  Created by Steve Gifford on 7/30/13.
 *  Copyright 2011-2015 mousebird consulting. All rights reserved.
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 */

#import "BillboardManager.h"
#import "NSDictionary+Stuff.h"
#import "UIColor+Stuff.h"

using namespace Eigen;
using namespace WhirlyKit;

@implementation WhirlyKitBillboardInfo

- (id)initWithBillboards:(NSArray *)billboards desc:(NSDictionary *)desc
{
    self = [super initWithDesc:desc];
    if (!self)
        return nil;
    
    _billboards = billboards;
    
    _color = [desc objectForKey:@"color" checkType:[UIColor class] default:[UIColor whiteColor]];
    _billboardId = Identifiable::genId();
    _zBufferRead = [desc floatForKey:@"zbufferread" default:true];
    _zBufferWrite = [desc floatForKey:@"zbufferwrite" default:true];
    
    return self;
}

@end

@implementation WhirlyKitBillboard
@end

namespace WhirlyKit
{
    
BillboardSceneRep::BillboardSceneRep()
{
}

BillboardSceneRep::BillboardSceneRep(SimpleIdentity inId)
: Identifiable(inId)
{
}

BillboardSceneRep::~BillboardSceneRep()
{
}

void BillboardSceneRep::clearContents(SelectionManager *selectManager,ChangeSet &changes,NSTimeInterval when)
{
    for (SimpleIDSet::iterator it = drawIDs.begin();
         it != drawIDs.end(); ++it)
        changes.push_back(new RemDrawableReq(*it,when));
    if (selectManager && !selectIDs.empty())
        selectManager->removeSelectables(selectIDs);
}

BillboardDrawableBuilder::BillboardDrawableBuilder(Scene *scene,ChangeSet &changes,BillboardSceneRep *sceneRep,WhirlyKitBillboardInfo *billInfo,SimpleIdentity billboardProgram,SimpleIdentity texId)
: scene(scene), changes(changes), sceneRep(sceneRep), billInfo(billInfo), drawable(NULL), billboardProgram(billboardProgram), texId(texId)
{
}

BillboardDrawableBuilder::~BillboardDrawableBuilder()
{
    flush();
}

void BillboardDrawableBuilder::addBillboard(Point3d center,const std::vector<WhirlyKit::Point2d> &pts,const std::vector<WhirlyKit::TexCoord> &texCoords,UIColor *inColor,const SingleVertexAttributeSet &vertAttrs)
{
    if (pts.size() != 4)
    {
        NSLog(@"Only expecting 4 point polygons in BillboardDrawableBuilder");
        return;
    }
    
    CoordSystemDisplayAdapter *coordAdapter = scene->getCoordAdapter();
    
    // Get the drawable ready
    if (!drawable || !drawable->compareVertexAttributes(vertAttrs) ||
        (drawable->getNumPoints()+4 > MaxDrawablePoints) ||
        (drawable->getNumTris()+2 > MaxDrawableTriangles))
    {
        if (drawable)
            flush();
        
        drawable = new BillboardDrawable();
        //        drawMbr.reset();
        drawable->setType(GL_TRIANGLES);
        [billInfo setupBasicDrawable:drawable];
        drawable->setProgram(billboardProgram);
        drawable->setTexId(0,texId);
        drawable->setRequestZBuffer(billInfo.zBufferRead);
        drawable->setWriteZBuffer(billInfo.zBufferWrite);
        if (!vertAttrs.empty())
        {
            SingleVertexAttributeInfoSet vertInfoSet;
            VertexAttributeSetConvert(vertAttrs,vertInfoSet);
            drawable->setVertexAttributes(vertInfoSet);
        }
        //        drawable->setForceZBufferOn(true);
    }
    
    RGBAColor color = [(inColor ? inColor : billInfo.color) asRGBAColor];
    
    Point3d centerOnSphere = center;
    double len = sqrt(centerOnSphere.x()*centerOnSphere.x() + centerOnSphere.y()*centerOnSphere.y() + centerOnSphere.z()*centerOnSphere.z());
    if (len != 0.0)
        centerOnSphere /= len;
    
    // Normal is straight up
    Point3d localPt = coordAdapter->displayToLocal(centerOnSphere);
    Point3d axisY = coordAdapter->normalForLocal(localPt);
    
    int startPoint = drawable->getNumPoints();
    for (unsigned int ii=0;ii<4;ii++)
    {
        drawable->addPoint(center);
        drawable->addOffset(Point3d(pts[ii].x(),pts[ii].y(),0.0));
        drawable->addTexCoord(0,texCoords[ii]);
        drawable->addNormal(axisY);
        drawable->addColor(color);
        if (!vertAttrs.empty())
            drawable->addVertexAttributes(vertAttrs);
    }
    drawable->addTriangle(BasicDrawable::Triangle(startPoint+0,startPoint+1,startPoint+2));
    drawable->addTriangle(BasicDrawable::Triangle(startPoint+0,startPoint+2,startPoint+3));
}

void BillboardDrawableBuilder::flush()
{
    if (drawable)
    {
        if (drawable->getNumPoints() > 0)
        {
            //            drawable->setLocalMbr(drawMbr);
            sceneRep->drawIDs.insert(drawable->getId());
            
            if (billInfo.fade > 0.0)
            {
                NSTimeInterval curTime = CFAbsoluteTimeGetCurrent();
                drawable->setFade(curTime, curTime+billInfo.fade);
            }
            changes.push_back(new AddDrawableReq(drawable));
        } else
            delete drawable;
        drawable = NULL;
    }
}


BillboardManager::BillboardManager()
{
    pthread_mutex_init(&billLock, NULL);
}

BillboardManager::~BillboardManager()
{
    pthread_mutex_destroy(&billLock);
    for (BillboardSceneRepSet::iterator it = sceneReps.begin();
         it != sceneReps.end(); ++it)
        delete *it;
    sceneReps.clear();
}

typedef std::map<SimpleIdentity,BillboardDrawableBuilder *> BuilderMap;

/// Add billboards for display
SimpleIdentity BillboardManager::addBillboards(NSArray *billboards,NSDictionary *desc,SimpleIdentity billShader,ChangeSet &changes)
{
    SelectionManager *selectManager = (SelectionManager *)scene->getManager(kWKSelectionManager);
    WhirlyKitBillboardInfo *billboardInfo = [[WhirlyKitBillboardInfo alloc] initWithBillboards:billboards desc:desc];

    BillboardSceneRep *sceneRep = new BillboardSceneRep(billboardInfo.billboardId);
    sceneRep->fade = billboardInfo.fade;
    
    CoordSystemDisplayAdapter *coordAdapter = scene->getCoordAdapter();
    
    // One builder per texture
    BuilderMap drawBuilders;
    
    // Work through the billboards, constructing as we go
    for (WhirlyKitBillboard *billboard in billboardInfo.billboards)
    {
        // Work through the individual polygons
        for (const SingleBillboardPoly &billPoly : billboard.polys)
        {
            BuilderMap::iterator it = drawBuilders.find(billPoly.texId);
            BillboardDrawableBuilder *drawBuilder = NULL;
            // Need a new one
            if (it == drawBuilders.end())
            {
                drawBuilder = new BillboardDrawableBuilder(scene,changes,sceneRep,billboardInfo,billShader,billPoly.texId);
                drawBuilders[billPoly.texId] = drawBuilder;
            } else
                drawBuilder = it->second;
            
            drawBuilder->addBillboard(billboard.center, billPoly.pts, billPoly.texCoords, billPoly.color, billPoly.vertexAttrs);
        }

        // While we're at it, let's add this to the selection layer
        if (selectManager && billboard.isSelectable)
        {
            // If the marker doesn't already have an ID, it needs one
            if (!billboard.selectID)
                billboard.selectID = Identifiable::genId();
            
            sceneRep->selectIDs.insert(billboard.selectID);
            
            // Normal is straight up
            Point3d localPt = coordAdapter->displayToLocal(billboard.center);
            Point3d axisY = coordAdapter->normalForLocal(localPt);

            selectManager->addSelectableBillboard(billboard.selectID, billboard.center, axisY, billboard.size, billboardInfo.minVis, billboardInfo.maxVis, billboardInfo.enable);
        }
    }
    
    // Flush out the changes and tear down the builders
    for (BuilderMap::iterator it = drawBuilders.begin();
         it != drawBuilders.end(); ++it)
    {
        BillboardDrawableBuilder *drawBuilder = it->second;
        drawBuilder->flush();
        delete drawBuilder;
    }
    drawBuilders.clear();

    SimpleIdentity billID = sceneRep->getId();

    pthread_mutex_lock(&billLock);
    sceneReps.insert(sceneRep);
    pthread_mutex_unlock(&billLock);
    
    return billID;
}
    
void BillboardManager::enableBillboards(SimpleIDSet &billIDs,bool enable,ChangeSet &changes)
{
    SelectionManager *selectManager = (SelectionManager *)scene->getManager(kWKSelectionManager);
    
    pthread_mutex_lock(&billLock);
    
    for (SimpleIDSet::iterator bit = billIDs.begin();bit != billIDs.end();++bit)
    {
        BillboardSceneRep dummyRep(*bit);
        BillboardSceneRepSet::iterator it = sceneReps.find(&dummyRep);
        if (it != sceneReps.end())
        {
            BillboardSceneRep *billRep = *it;
            for (SimpleIDSet::iterator dit = billRep->drawIDs.begin();
                 dit != billRep->drawIDs.end(); ++dit)
                changes.push_back(new OnOffChangeRequest((*dit), enable));

            if (selectManager && !billRep->selectIDs.empty())
                selectManager->enableSelectables(billRep->selectIDs, enable);
        }
    }
    
    pthread_mutex_unlock(&billLock);
}

/// Remove a group of billboards named by the given ID
void BillboardManager::removeBillboards(SimpleIDSet &billIDs,ChangeSet &changes)
{
    SelectionManager *selectManager = (SelectionManager *)scene->getManager(kWKSelectionManager);

    pthread_mutex_lock(&billLock);
    
    for (SimpleIDSet::iterator bit = billIDs.begin();bit != billIDs.end();++bit)
    {
        BillboardSceneRep dummyRep(*bit);
        BillboardSceneRepSet::iterator it = sceneReps.find(&dummyRep);
        NSTimeInterval curTime = CFAbsoluteTimeGetCurrent();
        if (it != sceneReps.end())
        {
            BillboardSceneRep *sceneRep = *it;
            
            NSTimeInterval removeTime = 0.0;
            if (sceneRep->fade > 0.0)
            {
                for (SimpleIDSet::iterator it = sceneRep->drawIDs.begin();
                     it != sceneRep->drawIDs.end(); ++it)
                    changes.push_back(new FadeChangeRequest(*it, curTime, curTime+sceneRep->fade));

                removeTime = curTime + sceneRep->fade;
            }
            
            sceneRep->clearContents(selectManager,changes,removeTime);
            sceneReps.erase(it);
            delete sceneRep;
        }
    }
    
    pthread_mutex_unlock(&billLock);
}

}
