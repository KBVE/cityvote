// AsyncRuntime is only available for native (non-WASM) targets
// WASM uses wasm-bindgen-futures::spawn_local instead of tokio

#[cfg(not(target_family = "wasm"))]
use std::{future::Future, sync::Arc};

#[cfg(not(target_family = "wasm"))]
use godot::{classes::Engine, prelude::*};

#[cfg(not(target_family = "wasm"))]
use tokio::{
    runtime::{self, Runtime},
    task::JoinHandle,
};

#[cfg(not(target_family = "wasm"))]
/// AsyncRuntime singleton for managing tokio runtime in Godot
/// Based on godot_tokio pattern for proper tokio/Godot integration
#[derive(GodotClass)]
#[class(base=Object)]
pub struct AsyncRuntime {
    base: Base<Object>,
    runtime: Arc<Runtime>,
}

#[cfg(not(target_family = "wasm"))]
#[godot_api]
impl IObject for AsyncRuntime {
    fn init(base: Base<Object>) -> Self {
        // Use multi-threaded runtime for WebSocket connections
        let runtime = runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("Failed to create tokio runtime");

        godot_print!("[IRC] AsyncRuntime singleton initialized with multi-threaded runtime");

        Self {
            base,
            runtime: Arc::new(runtime),
        }
    }
}

#[cfg(not(target_family = "wasm"))]
#[godot_api]
impl AsyncRuntime {
    pub const SINGLETON: &'static str = "AsyncRuntime";

    /// Gets the singleton instance
    fn singleton() -> Option<Gd<AsyncRuntime>> {
        match Engine::singleton().get_singleton(Self::SINGLETON) {
            Some(singleton) => Some(singleton.cast::<Self>()),
            None => None,
        }
    }

    /// Gets the active runtime under the AsyncRuntime singleton
    /// Automatically registers the singleton if not found
    pub fn runtime() -> Arc<Runtime> {
        match Self::singleton() {
            Some(singleton) => {
                let bind = singleton.bind();
                Arc::clone(&bind.runtime)
            }
            None => {
                // Auto-register as failsafe
                godot_print!("[IRC] AsyncRuntime singleton not found, auto-registering");
                Engine::singleton()
                    .register_singleton(AsyncRuntime::SINGLETON, &AsyncRuntime::new_alloc());

                let singleton = Self::singleton()
                    .expect("Engine was not able to register AsyncRuntime singleton!");

                let bind = singleton.bind();
                Arc::clone(&bind.runtime)
            }
        }
    }

    /// Wrapper for tokio::spawn
    pub fn spawn<F>(future: F) -> tokio::task::JoinHandle<F::Output>
    where
        F: Future + Send + 'static,
        F::Output: Send + 'static,
    {
        Self::runtime().spawn(future)
    }

    /// Wrapper for tokio::block_on
    pub fn block_on<F>(future: F) -> F::Output
    where
        F: Future,
    {
        Self::runtime().block_on(future)
    }

    /// Wrapper for tokio::spawn_blocking
    pub fn spawn_blocking<F, R>(func: F) -> JoinHandle<R>
    where
        F: FnOnce() -> R + Send + 'static,
        R: Send + 'static,
    {
        Self::runtime().spawn_blocking(func)
    }
}
