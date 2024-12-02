CREATE INDEX IF NOT EXISTS l2block_block_hash_idx ON state.l2block (block_hash);
CREATE INDEX IF NOT EXISTS l2block_created_at_idx ON state.l2block (created_at);
CREATE INDEX IF NOT EXISTS log_log_index_idx ON state.log (log_index);
CREATE INDEX IF NOT EXISTS log_topic0_idx ON state.log (topic0);
CREATE INDEX IF NOT EXISTS log_topic1_idx ON state.log (topic1);
CREATE INDEX IF NOT EXISTS log_topic2_idx ON state.log (topic2);
CREATE INDEX IF NOT EXISTS log_topic3_idx ON state.log (topic3);
CREATE INDEX IF NOT EXISTS idx_receipt_tx_index ON state.receipt (block_num, tx_index);
CREATE INDEX IF NOT EXISTS receipt_block_num_idx ON state.receipt USING btree (block_num);