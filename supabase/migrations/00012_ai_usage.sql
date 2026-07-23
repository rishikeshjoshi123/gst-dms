CREATE TABLE model_pricing (
    model_name TEXT PRIMARY KEY,
    input_price_per_1m NUMERIC(10, 4) NOT NULL,
    output_price_per_1m NUMERIC(10, 4) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Insert initial pricing
-- Gemini 1.5 Flash (multimodal): $0.075 / 1M input, $0.30 / 1M output
-- Text Embedding 004: $0.025 / 1M characters (input only) - We will treat characters as tokens here or manage it via input_tokens
INSERT INTO model_pricing (model_name, input_price_per_1m, output_price_per_1m) VALUES
('gemini-2.5-flash', 0.075, 0.30),
('text-embedding-004', 0.025, 0.0);

CREATE TABLE ai_usage_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id UUID NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    document_id UUID REFERENCES documents(id) ON DELETE SET NULL,
    operation_type TEXT NOT NULL,
    model_name TEXT NOT NULL REFERENCES model_pricing(model_name) ON DELETE RESTRICT,
    input_tokens INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    total_cost_usd NUMERIC(10, 6) NOT NULL DEFAULT 0.0,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- RLS for model_pricing
ALTER TABLE model_pricing ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read model pricing" ON model_pricing FOR SELECT USING (true);

-- RLS for ai_usage_logs
ALTER TABLE ai_usage_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view usage logs for their org" 
    ON ai_usage_logs FOR SELECT 
    USING (org_id IN (SELECT org_id FROM org_members WHERE user_id = auth.uid()));
CREATE POLICY "Users can insert usage logs for their org" 
    ON ai_usage_logs FOR INSERT 
    WITH CHECK (org_id IN (SELECT org_id FROM org_members WHERE user_id = auth.uid()));

