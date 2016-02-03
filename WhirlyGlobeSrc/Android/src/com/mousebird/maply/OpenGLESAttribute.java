/*
 *  OpenGLESAttribute.java
 *  WhirlyGlobeLib
 *
 *  Created by jmnavarro
 *  Copyright 2011-2015 mousebird consulting
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
package com.mousebird.maply;

public class OpenGLESAttribute {

    public OpenGLESAttribute(){
        initialise();
    }

    public void finalise(){
        dispose();
    }

    public native boolean isArray();

    public native boolean isType(int type);

    public native void setName (String name);

    public native String getName();

    public native void setIndex(int index);

    public native int getIndex();

    public native void setSize(int size);

    public native int getSize();

    public native void setType (int type);

    public native int getType();

    private static native void nativeInit();

    native void initialise();
    native void dispose();

    private long nativeHandle;

}