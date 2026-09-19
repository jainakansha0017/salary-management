SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;


--
-- Name: EXTENSION btree_gist; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION btree_gist IS 'support for indexing common datatypes in GiST';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: currencies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.currencies (
    code character varying(3) NOT NULL,
    name character varying NOT NULL,
    symbol character varying NOT NULL,
    minor_unit integer DEFAULT 2 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT currencies_minor_unit_range CHECK (((minor_unit >= 0) AND (minor_unit <= 4)))
);


--
-- Name: departments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departments (
    id bigint NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: departments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.departments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: departments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.departments_id_seq OWNED BY public.departments.id;


--
-- Name: employees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employees (
    id bigint NOT NULL,
    employee_number character varying NOT NULL,
    first_name character varying NOT NULL,
    last_name character varying NOT NULL,
    email character varying NOT NULL,
    country_code character varying(2) NOT NULL,
    department_id bigint NOT NULL,
    job_title character varying NOT NULL,
    job_level character varying NOT NULL,
    hired_on date NOT NULL,
    ended_on date,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: COLUMN employees.country_code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employees.country_code IS 'ISO 3166-1 alpha-2';


--
-- Name: COLUMN employees.job_level; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employees.job_level IS 'pay band; the peer group for comparisons';


--
-- Name: COLUMN employees.ended_on; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employees.ended_on IS 'null while employed';


--
-- Name: employees_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.employees_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employees_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.employees_id_seq OWNED BY public.employees.id;


--
-- Name: exchange_rates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.exchange_rates (
    id bigint NOT NULL,
    from_currency_code character varying(3) NOT NULL,
    to_currency_code character varying(3) NOT NULL,
    rate numeric(18,8) NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT exchange_rates_period_ordered CHECK (((effective_to IS NULL) OR (effective_to > effective_from))),
    CONSTRAINT exchange_rates_rate_positive CHECK ((rate > (0)::numeric))
);


--
-- Name: COLUMN exchange_rates.effective_to; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.exchange_rates.effective_to IS 'null means this is the current rate';


--
-- Name: exchange_rates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.exchange_rates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: exchange_rates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.exchange_rates_id_seq OWNED BY public.exchange_rates.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: departments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments ALTER COLUMN id SET DEFAULT nextval('public.departments_id_seq'::regclass);


--
-- Name: employees id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees ALTER COLUMN id SET DEFAULT nextval('public.employees_id_seq'::regclass);


--
-- Name: exchange_rates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_rates ALTER COLUMN id SET DEFAULT nextval('public.exchange_rates_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: currencies currencies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.currencies
    ADD CONSTRAINT currencies_pkey PRIMARY KEY (code);


--
-- Name: departments departments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_pkey PRIMARY KEY (id);


--
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (id);


--
-- Name: exchange_rates exchange_rates_no_overlapping_periods; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_rates
    ADD CONSTRAINT exchange_rates_no_overlapping_periods EXCLUDE USING gist (from_currency_code WITH =, to_currency_code WITH =, daterange(effective_from, effective_to, '[)'::text) WITH &&);


--
-- Name: exchange_rates exchange_rates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_rates
    ADD CONSTRAINT exchange_rates_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: index_departments_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_departments_on_name ON public.departments USING btree (name);


--
-- Name: index_employees_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_employees_on_active ON public.employees USING btree (id) WHERE (ended_on IS NULL);


--
-- Name: index_employees_on_country_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_employees_on_country_code ON public.employees USING btree (country_code);


--
-- Name: index_employees_on_department_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_employees_on_department_id ON public.employees USING btree (department_id);


--
-- Name: index_employees_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_employees_on_email ON public.employees USING btree (email);


--
-- Name: index_employees_on_employee_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_employees_on_employee_number ON public.employees USING btree (employee_number);


--
-- Name: index_employees_on_job_level; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_employees_on_job_level ON public.employees USING btree (job_level);


--
-- Name: index_exchange_rates_on_pair_and_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_exchange_rates_on_pair_and_start ON public.exchange_rates USING btree (from_currency_code, to_currency_code, effective_from);


--
-- Name: employees fk_rails_0025f65a97; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT fk_rails_0025f65a97 FOREIGN KEY (department_id) REFERENCES public.departments(id);


--
-- Name: exchange_rates fk_rails_d724569440; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_rates
    ADD CONSTRAINT fk_rails_d724569440 FOREIGN KEY (from_currency_code) REFERENCES public.currencies(code);


--
-- Name: exchange_rates fk_rails_e3c6b8452b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.exchange_rates
    ADD CONSTRAINT fk_rails_e3c6b8452b FOREIGN KEY (to_currency_code) REFERENCES public.currencies(code);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260919100400'),
('20260919100300'),
('20260919100200'),
('20260919100100'),
('20260919100000');

