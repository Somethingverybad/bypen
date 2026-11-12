package com.hyax.bypen

import android.app.Application

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        Store.init(this)
        TunnelLog.tag = "app"
    }
}
