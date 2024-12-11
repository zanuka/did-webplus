/// This will run once at load time (i.e. presumably before main function is called).
#[ctor::ctor]
fn overall_init() {
    // Ignore errors, since there may not be a .env file (e.g. in docker image)
    let _ = dotenvy::dotenv();

    // It's necessary to specify EnvFilter::from_default_env in order to use RUST_LOG env var.
    // TODO: Make env var to control full/compact/pretty/json formatting of logs
    tracing_subscriber::fmt()
        .with_target(true)
        .with_line_number(true)
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .compact()
        .init();
}

#[tokio::test]
async fn test_software_wallet() {
    // TODO: Use env vars to be able to point to a "real" VDR.

    let vdr_database_path = "tests/test_software_wallet.vdr.db";
    let wallet_database_path = "tests/test_software_wallet.wallet-store.db";

    // Delete any existing database files so that we're starting from a consistent, blank start every time.
    // The postgres equivalent of this would be to drop and recreate the relevant databases.
    if std::fs::exists(vdr_database_path).expect("pass") {
        std::fs::remove_file(vdr_database_path).expect("pass");
    }
    if std::fs::exists(wallet_database_path).expect("pass") {
        std::fs::remove_file(wallet_database_path).expect("pass");
    }

    let vdr_config = did_webplus_vdr_lib::VDRConfig {
        did_host: "localhost".to_string(),
        did_port_o: Some(11085),
        listen_port: 11085,
        database_url: format!("sqlite://{}?mode=rwc", vdr_database_path),
        database_max_connections: 10,
        gateways: Vec::new(),
    };
    let vdr_handle = did_webplus_vdr_lib::spawn_vdr(vdr_config.clone())
        .await
        .expect("pass");

    let sqlite_pool =
        sqlx::SqlitePool::connect(format!("sqlite://{}?mode=rwc", wallet_database_path).as_str())
            .await
            .expect("pass");
    let wallet_storage =
        did_webplus_wallet_storage_sqlite::WalletStorageSQLite::open_and_run_migrations(
            sqlite_pool,
        )
        .await
        .expect("pass");

    test_util::wait_until_service_is_up(
        "VDR",
        format!("http://localhost:{}/health", vdr_config.listen_port).as_str(),
    )
    .await;

    use did_webplus_doc_store::DIDDocStorage;
    let mut transaction = wallet_storage.begin_transaction(None).await.expect("pass");
    let software_wallet = did_webplus_software_wallet::SoftwareWallet::create(
        &mut transaction,
        &wallet_storage,
        Some("fancy wallet".to_string()),
    )
    .await
    .expect("pass");
    wallet_storage
        .commit_transaction(transaction)
        .await
        .expect("pass");

    let vdr_scheme = "http";
    let vdr_did_create_endpoint = format!(
        "{}://{}:{}",
        vdr_scheme, vdr_config.did_host, vdr_config.listen_port
    );

    use did_webplus_wallet::Wallet;

    let controlled_did = software_wallet
        .create_did(vdr_did_create_endpoint.as_str())
        .await
        .expect("pass");
    let did = controlled_did.did();
    tracing::debug!("created DID: {} - fully qualified: {}", did, controlled_did);

    let controlled_did = software_wallet
        .update_did(&did, vdr_scheme)
        .await
        .expect("pass");
    tracing::debug!("updated DID: {}", controlled_did);

    tracing::info!("Shutting down VDR");
    vdr_handle.abort();
}
