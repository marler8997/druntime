/**
 * Contains the external GC interface.
 *
 * Copyright: Copyright Digital Mars 2005 - 2016.
 * License:   $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors:   Walter Bright, Sean Kelly
 */

/*          Copyright Digital Mars 2005 - 2016.
 * Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */
module gc.proxy;

import gc.impl.conservative.gc;
import gc.impl.manual.gc;
import gc.config;
import gc.gcinterface;
import core.atomic : atomicLoad, MemoryOrder;

static import core.memory;

private
{
    static import core.memory;
    alias BlkInfo = core.memory.GC.BlkInfo;

    extern (C) void thread_init();
    extern (C) void thread_term();

    import core.internal.spinlock;
    static SpinLock instanceLock;

    __gshared GC instance;
    __gshared GC proxiedGC; // used to iterate roots of Windows DLLs
}

extern (C)
{
    struct gc_vtable
    {
        void function() init;
        void function() term;
        void function() enable;
        void function() disable;
        void function() nothrow collect;
        void function() nothrow minimize;
        uint function( void* p ) nothrow getAttr;
        uint function( void* p, uint a ) nothrow setAttr;
        uint function( void* p, uint a ) nothrow clrAttr;
        void* function( size_t sz, uint ba = 0, const TypeInfo ti = null ) nothrow malloc;
        BlkInfo function( size_t sz, uint ba = 0, const TypeInfo ti = null ) nothrow qalloc;
        void* function( size_t sz, uint ba = 0, const TypeInfo ti = null ) nothrow calloc;
        void* function( void* p, size_t sz, uint ba = 0, const TypeInfo ti = null ) nothrow realloc;
        size_t function( void* p, size_t mx, size_t sz, const TypeInfo ti = null ) nothrow extend;
        size_t function( size_t sz ) nothrow reserve;
        void function( void* p ) nothrow @nogc free;
        void* function( void* p ) nothrow @nogc addrOf;
        size_t function( void* p ) nothrow @nogc sizeOf;
        BlkInfo function( void* p ) nothrow query;
        core.memory.GC.Stats function() nothrow stats;
        void function( void* p ) nothrow addRoot;
        void function( void* p, size_t sz, const TypeInfo ti = null ) nothrow addRange;
        void function( void* p ) nothrow removeRoot;
        void function( void* p ) nothrow removeRange;
        void function( in void[] segment ) nothrow runFinalizers;
        bool function() nothrow inFinalizer;
        GC function() nothrow getProxy;
        void function( GC proxy ) setProxy;
        void function() clrProxy;
    }
    private __gshared const(gc_vtable)* _current_vtable = &before_init_vtable;
    @property private ref const(gc_vtable) currentVtable() nothrow @nogc
    {
        //return atomicLoad!(MemoryOrder.acq)(*&_current_vtable);
	return *_current_vtable;
    }

    private GC createGC()
    {
        GC newInstance;
        config.initialize();
        ManualGC.initialize(newInstance);
        ConservativeGC.initialize(newInstance);
        if (newInstance is null)
        {
            import core.stdc.stdio : fprintf, stderr;
            import core.stdc.stdlib : exit;

            fprintf(stderr, "No GC was initialized, please recheck the name of the selected GC ('%.*s').\n", cast(int)config.gc.length, config.gc.ptr);
            exit(1);
        }

        // NOTE: The GC must initialize the thread library
        //       before its first collection.
        thread_init();
	return newInstance;
    }
    private void init_no_throw() nothrow
    {
        try
	{
	    initImpl();
	}
	catch (Exception e)
	{
	    assert(0, e.msg);
	}
    }
    private void init()
    {
        auto pInstance = cast(shared(GC)*)&instance;

	// double-checked lock
	if (atomicLoad!(MemoryOrder.acq)(*pInstance) is null)
	{
	    synchronized(instanceLock)
	    {
                if (atomicLoad!(MemoryOrder.acq)(*pInstance) is null)
		{
                    atomicStore(*pInstance, cast(shared GC)createGC());
		    auto pVtable = &_current_vtable;
		    
		    cast(shared gc_vtable)after_init_vtable;
		}
	    }
	}
    }

private __gshared immutable before_init_vtable = gc_vtable(
    // init
    &init,
    // term
    &common_gc_term,
    // enable
    function void() { init(); gc_enable(); },
    // disable
    function void() { /* Do Nothing */ },
    // collect
    function void() nothrow { init(); gc_collect(); },
    // minimize
    function void() nothrow { init(); gc_minimize(); },
    // getAttr
    function uint( void* p ) nothrow
    {
        return instance.getAttr(p);
    },
    // setAttr
    function uint( void* p, uint a ) nothrow
    {
        return instance.setAttr(p, a);
    },
    // clrAttr
    function uint( void* p, uint a ) nothrow
    {
        return instance.clrAttr(p, a);
    },
    // malloc
    function void*( size_t sz, uint ba = 0, const TypeInfo ti = null ) nothrow
    {
        return instance.malloc(sz, ba, ti);
    },
    // qalloc
    function BlkInfo( size_t sz, uint ba = 0, const TypeInfo ti = null ) nothrow
    {
        return instance.qalloc( sz, ba, ti );
    },
    // calloc
    function void*( size_t sz, uint ba = 0, const TypeInfo ti = null ) nothrow
    {
        return instance.calloc( sz, ba, ti );
    },
    // realloc
    function void*( void* p, size_t sz, uint ba = 0, const TypeInfo ti = null ) nothrow
    {
        return instance.realloc( p, sz, ba, ti );
    },
    // extend
    function size_t( void* p, size_t mx, size_t sz, const TypeInfo ti = null ) nothrow
    {
        return instance.extend( p, mx, sz,ti );
    },
    // reserve
    function size_t( size_t sz ) nothrow
    {
        return instance.reserve( sz );
    },
    // free
    function void( void* p ) nothrow @nogc
    {
        return instance.free( p );
    },
    // addrOr
    function void*( void* p ) nothrow @nogc
    {
        return instance.addrOf( p );
    },
    // sizeOf
    function size_t( void* p ) nothrow @nogc
    {
        return instance.sizeOf( p );
    },
    // query
    function BlkInfo( void* p ) nothrow
    {
        return instance.query( p );
    },
    // stats
    function core.memory.GC.Stats() nothrow
    {
        return instance.stats();
    },
    // addRoot
    function void( void* p ) nothrow
    {
        return instance.addRoot( p );
    },
    // addRange
    function void( void* p, size_t sz, const TypeInfo ti = null ) nothrow
    {
        return instance.addRange( p, sz, ti );
    },
    // removeRoot
    function void( void* p ) nothrow
    {
        return instance.removeRoot( p );
    },
    // removeRange
    function void( void* p ) nothrow
    {
        return instance.removeRange( p );
    },
    // runFinalizers
    function void( in void[] segment ) nothrow
    {
        return instance.runFinalizers( segment );
    },
    // inFinalizer
    function bool() nothrow
    {
        return instance.inFinalizer();
    },
    // getProxy
    function GC() nothrow
    {
        return instance;
    },
    // setProxy
    function void( GC proxy )
    {
        foreach(root; instance.rootIter)
        {
            proxy.addRoot(root);
        }
        foreach(range; instance.rangeIter)
        {
            proxy.addRange(range.pbot, range.ptop - range.pbot, range.ti);
        }

        proxiedGC = instance; // remember initial GC to later remove roots
        instance = proxy;
    },
    // clrProxy
    function void()
    {
        foreach(root; proxiedGC.rootIter)
        {
            instance.removeRoot(root);
        }
        foreach(range; proxiedGC.rangeIter)
        {
            instance.removeRange(range);
        }

        instance = proxiedGC;
        proxiedGC = null;
    }
    );



////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
private __gshared immutable after_init_vtable = gc_vtable(
    // init
    function void() { /* GC Already Initialized */ },
    // term
    &common_gc_term,
    // enable
    function void()
    {
        instance.enable();
    },
    // disable
    function void()
    {
        instance.disable();
    },
    // collect
    function void() nothrow
    {
        instance.collect();
    },
    // minimize
    function void() nothrow
    {
        instance.minimize();
    },
    // getAttr
    function uint( void* p ) nothrow
    {
        return instance.getAttr(p);
    },
    // setAttr
    function uint( void* p, uint a ) nothrow
    {
        return instance.setAttr(p, a);
    },
    // clrAttr
    function uint( void* p, uint a ) nothrow
    {
        return instance.clrAttr(p, a);
    },
    // malloc
    function void*( size_t sz, uint ba = 0, const TypeInfo ti = null ) nothrow
    {
        return instance.malloc(sz, ba, ti);
    },
    // qalloc
    function BlkInfo( size_t sz, uint ba = 0, const TypeInfo ti = null ) nothrow
    {
        return instance.qalloc( sz, ba, ti );
    },
    // calloc
    function void*( size_t sz, uint ba = 0, const TypeInfo ti = null ) nothrow
    {
        return instance.calloc( sz, ba, ti );
    },
    // realloc
    function void*( void* p, size_t sz, uint ba = 0, const TypeInfo ti = null ) nothrow
    {
        return instance.realloc( p, sz, ba, ti );
    },
    // extend
    function size_t( void* p, size_t mx, size_t sz, const TypeInfo ti = null ) nothrow
    {
        return instance.extend( p, mx, sz,ti );
    },
    // reserve
    function size_t( size_t sz ) nothrow
    {
        return instance.reserve( sz );
    },
    // free
    function void( void* p ) nothrow @nogc
    {
        return instance.free( p );
    },
    // addrOr
    function void*( void* p ) nothrow @nogc
    {
        return instance.addrOf( p );
    },
    // sizeOf
    function size_t( void* p ) nothrow @nogc
    {
        return instance.sizeOf( p );
    },
    // query
    function BlkInfo( void* p ) nothrow
    {
        return instance.query( p );
    },
    // stats
    function core.memory.GC.Stats() nothrow
    {
        return instance.stats();
    },
    // addRoot
    function void( void* p ) nothrow
    {
        return instance.addRoot( p );
    },
    // addRange
    function void( void* p, size_t sz, const TypeInfo ti = null ) nothrow
    {
        return instance.addRange( p, sz, ti );
    },
    // removeRoot
    function void( void* p ) nothrow
    {
        return instance.removeRoot( p );
    },
    // removeRange
    function void( void* p ) nothrow
    {
        return instance.removeRange( p );
    },
    // runFinalizers
    function void( in void[] segment ) nothrow
    {
        return instance.runFinalizers( segment );
    },
    // inFinalizer
    function bool() nothrow
    {
        return instance.inFinalizer();
    },
    // getProxy
    function GC() nothrow
    {
        return instance;
    },
    // setProxy
    function void( GC proxy )
    {
        foreach(root; instance.rootIter)
        {
            proxy.addRoot(root);
        }
        foreach(range; instance.rangeIter)
        {
            proxy.addRange(range.pbot, range.ptop - range.pbot, range.ti);
        }

        proxiedGC = instance; // remember initial GC to later remove roots
        instance = proxy;
    },
    // clrProxy
    function void()
    {
        foreach(root; proxiedGC.rootIter)
        {
            instance.removeRoot(root);
        }
        foreach(range; proxiedGC.rangeIter)
        {
            instance.removeRange(range);
        }

        instance = proxiedGC;
        proxiedGC = null;
    }
    );












    void gc_init() { currentVtable.init(); }
    void gc_term() { currentVtable.term(); }
    void gc_enable() { currentVtable.enable(); }
    void gc_disable() { currentVtable.disable(); }
    void gc_collect() nothrow { currentVtable.collect(); }
    void gc_minimize() nothrow { currentVtable.minimize(); }

    uint gc_getAttr( void* p ) nothrow { return currentVtable.getAttr(p); }
    uint gc_setAttr( void* p, uint a ) nothrow { return currentVtable.setAttr(p, a); }
    uint gc_clrAttr( void* p, uint a ) nothrow { return currentVtable.clrAttr(p, a); }

    void* gc_malloc( size_t sz, uint ba = 0, const TypeInfo ti = null ) nothrow
    {
        return currentVtable.malloc(sz, ba, ti);
    }
    BlkInfo gc_qalloc( size_t sz, uint ba = 0, const TypeInfo ti = null ) nothrow
    {
        return currentVtable.qalloc(sz, ba, ti);
    }
    void* gc_calloc( size_t sz, uint ba = 0, const TypeInfo ti = null ) nothrow
    {
        return currentVtable.calloc(sz, ba, ti);
    }
    void* gc_realloc( void* p, size_t sz, uint ba = 0, const TypeInfo ti = null ) nothrow
    {
        return currentVtable.realloc(p, sz, ba, ti);
    }
    size_t gc_extend( void* p, size_t mx, size_t sz, const TypeInfo ti = null ) nothrow
    {
        return currentVtable.extend(p, mx, sz, ti);
    }

    size_t gc_reserve( size_t sz ) nothrow { return currentVtable.reserve(sz); }
    void gc_free( void* p ) nothrow @nogc { currentVtable.free(p); }
    void* gc_addrOf( void* p ) nothrow @nogc { return currentVtable.addrOf(p); }
    size_t gc_sizeOf( void* p ) nothrow @nogc { return currentVtable.sizeOf(p); }
    BlkInfo gc_query( void* p ) nothrow { return currentVtable.query(p); }
    core.memory.GC.Stats gc_stats() nothrow { return currentVtable.stats(); }
    void gc_addRoot( void* p ) nothrow { return currentVtable.addRoot(p); }
    void gc_addRange( void* p, size_t sz, const TypeInfo ti = null ) nothrow
    {
        return currentVtable.addRange( p, sz, ti );
    }
    void gc_removeRoot( void* p ) nothrow
    {
        return currentVtable.removeRoot( p );
    }

    void gc_removeRange( void* p ) nothrow
    {
        return currentVtable.removeRange( p );
    }

    void gc_runFinalizers( in void[] segment ) nothrow
    {
        return currentVtable.runFinalizers( segment );
    }

    bool gc_inFinalizer() nothrow
    {
        return currentVtable.inFinalizer();
    }

    GC gc_getProxy() nothrow
    {
        return currentVtable.getProxy();
    }

    export
    {
        void gc_setProxy( GC proxy )
        {
	    currentVtable.setProxy(proxy);
        }
        void gc_clrProxy()
        {
	    currentVtable.clrProxy();
        }
    }


    private void common_gc_term()
    {
        // NOTE: There may be daemons threads still running when this routine is
        //       called.  If so, cleaning memory out from under then is a good
        //       way to make them crash horribly.  This probably doesn't matter
        //       much since the app is supposed to be shutting down anyway, but
        //       I'm disabling cleanup for now until I can think about it some
        //       more.
        //
        // NOTE: Due to popular demand, this has been re-enabled.  It still has
        //       the problems mentioned above though, so I guess we'll see.

        instance.collectNoStack(); // not really a 'collect all' -- still scans
                                    // static data area, roots, and ranges.

        thread_term();

        ManualGC.finalize(instance);
        ConservativeGC.finalize(instance);
    }

}
