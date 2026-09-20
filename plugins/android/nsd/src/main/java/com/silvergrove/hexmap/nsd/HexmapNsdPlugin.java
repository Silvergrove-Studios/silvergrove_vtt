package com.silvergrove.hexmap.nsd;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Build;
import android.util.Log;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.net.InetAddress;
import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * Service discovery through Android's own NsdManager. The system's mDNS
 * daemon owns port 5353 and receives the multicast that routers reflect
 * between subnets; nothing an app opens itself can. Godot sees this as the
 * "HexmapNsd" singleton with signals:
 *   service_found(name, host, port, addresses)   resolved, ready to connect
 *   service_lost(name)
 *   discovery_state(text)                        for a diagnostics line
 */
public class HexmapNsdPlugin extends GodotPlugin {
    private static final String TAG = "HexmapNsd";
    private NsdManager nsd;
    private NsdManager.DiscoveryListener listener;
    private String serviceType = "";
    // NsdManager resolves one service at a time; queue the rest.
    private final ArrayDeque<NsdServiceInfo> toResolve = new ArrayDeque<>();
    private boolean resolving = false;

    public HexmapNsdPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "HexmapNsd";
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        return new HashSet<>(Arrays.asList(
                new SignalInfo("service_found", String.class, String.class, Integer.class, String[].class),
                new SignalInfo("service_lost", String.class),
                new SignalInfo("discovery_state", String.class)));
    }

    private NsdManager manager() {
        if (nsd == null) {
            Context ctx = getActivity() != null ? getActivity() : getGodot().getContext();
            nsd = (NsdManager) ctx.getSystemService(Context.NSD_SERVICE);
        }
        return nsd;
    }

    /** Start browsing for a service type such as "_hexmap._tcp." (trailing dot optional). */
    @UsedByGodot
    public boolean startDiscovery(String type) {
        stopDiscovery();
        serviceType = type.endsWith(".") ? type : type + ".";
        NsdManager m = manager();
        if (m == null) {
            emitSignal("discovery_state", "NSD unavailable");
            return false;
        }
        listener = new NsdManager.DiscoveryListener() {
            @Override public void onStartDiscoveryFailed(String t, int code) { emitSignal("discovery_state", "NSD start failed " + code); }
            @Override public void onStopDiscoveryFailed(String t, int code) { }
            @Override public void onDiscoveryStarted(String t) { emitSignal("discovery_state", "NSD browsing"); }
            @Override public void onDiscoveryStopped(String t) { emitSignal("discovery_state", "NSD stopped"); }
            @Override public void onServiceFound(NsdServiceInfo info) {
                synchronized (toResolve) { toResolve.add(info); }
                resolveNext();
            }
            @Override public void onServiceLost(NsdServiceInfo info) { emitSignal("service_lost", info.getServiceName()); }
        };
        try {
            m.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, listener);
            return true;
        } catch (Exception e) {
            Log.w(TAG, "discoverServices failed", e);
            emitSignal("discovery_state", "NSD error: " + e.getMessage());
            listener = null;
            return false;
        }
    }

    @UsedByGodot
    public void stopDiscovery() {
        if (nsd != null && listener != null) {
            try { nsd.stopServiceDiscovery(listener); } catch (Exception ignored) { }
        }
        listener = null;
        synchronized (toResolve) { toResolve.clear(); }
        resolving = false;
    }

    private void resolveNext() {
        NsdServiceInfo next;
        synchronized (toResolve) {
            if (resolving) return;
            next = toResolve.poll();
            if (next == null) return;
            resolving = true;
        }
        try {
            manager().resolveService(next, new NsdManager.ResolveListener() {
                @Override public void onResolveFailed(NsdServiceInfo info, int code) {
                    Log.w(TAG, "resolve failed " + code + " for " + info.getServiceName());
                    done();
                }
                @Override public void onServiceResolved(NsdServiceInfo info) {
                    List<InetAddress> hosts = Collections.emptyList();
                    if (Build.VERSION.SDK_INT >= 34) {
                        hosts = info.getHostAddresses();
                    } else if (info.getHost() != null) {
                        hosts = Collections.singletonList(info.getHost());
                    }
                    String first = "";
                    java.util.ArrayList<String> addrs = new java.util.ArrayList<>();
                    for (InetAddress a : hosts) {
                        String s = a.getHostAddress();
                        if (s == null || s.contains(":")) continue;   // IPv4 only, like the rest of Hexmap
                        if (first.isEmpty()) first = s;
                        addrs.add(s);
                    }
                    if (!first.isEmpty()) {
                        emitSignal("service_found", info.getServiceName(), first, info.getPort(), addrs.toArray(new String[0]));
                    }
                    done();
                }
                private void done() {
                    synchronized (toResolve) { resolving = false; }
                    resolveNext();
                }
            });
        } catch (Exception e) {
            Log.w(TAG, "resolveService failed", e);
            synchronized (toResolve) { resolving = false; }
        }
    }

    @Override
    public void onMainDestroy() {
        stopDiscovery();
        super.onMainDestroy();
    }
}
