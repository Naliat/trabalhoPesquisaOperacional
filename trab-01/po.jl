# ENV["GKSwstype"] = "100"

using JuMP
using Gurobi
using Printf
using DelimitedFiles
using ProgressMeter
using Plots
using Random

function obter_info_hardware()
    modelo_cpu = Sys.CPU_NAME
    if Sys.islinux() && isfile("/proc/cpuinfo")
        for linha in readlines("/proc/cpuinfo")
            if startswith(linha, "model name")
                partes = split(linha, ":")
                if length(partes) > 1
                    modelo_cpu = strip(partes[2])
                    break
                end
            end
        end
    end

    ram_gb = Sys.total_memory() / (1024^3)
    cores_fisicos = Sys.CPU_THREADS

    return (
        so = string(Sys.KERNEL, " ", Sys.ARCH),
        cpu = modelo_cpu,
        threads = cores_fisicos,
        ram = @sprintf("%.2f GB", ram_gb),
        julia_v = string(VERSION)
    )
end

function verificar_caminho_valido(n::Int, arcos::Vector{Tuple{Int, Int}}, s::Int, t::Int)
    if length(arcos) != n - 1
        return false
    end

    grau_saida = zeros(Int, n)
    grau_entrada = zeros(Int, n)
    adj = Dict{Int, Int}()

    for (u, v) in arcos
        if u < 1 || u > n || v < 1 || v > n || u == v
            return false
        end
        grau_saida[u] += 1
        grau_entrada[v] += 1
        adj[u] = v
    end

    if grau_saida[s] != 1 || grau_entrada[s] != 0
        return false
    end

    if grau_entrada[t] != 1 || grau_saida[t] != 0
        return false
    end

    for k in 1:n
        if k != s && k != t
            if grau_saida[k] != 1 || grau_entrada[k] != 1
                return false
            end
        end
    end

    visitados = Set{Int}([s])
    atual = s
    while haskey(adj, atual)
        proximo = adj[atual]
        if in(proximo, visitados)
            return false
        end
        push!(visitados, proximo)
        atual = proximo
    end

    return (atual == t) && (length(visitados) == n)
end

function resolver_pchm_gurobi(n::Int, C::Matrix{Float64}; s::Int=1, t::Int=n, relaxacao::Bool=false, time_limit_sec::Float64=180.0)
    V = 1:n
    model = Model(Gurobi.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, time_limit_sec)

    if relaxacao
        @variable(model, 0.0 <= x[i in V, j in V] <= 1.0)
        @variable(model, u[i in V] >= 0.0)
    else
        @variable(model, x[i in V, j in V], Bin)
        @variable(model, u[i in V] >= 0, Int)
    end

    @objective(model, Min, sum(C[i, j] * x[i, j] for i in V, j in V if i != j))

    for i in V
        @constraint(model, x[i, i] == 0)
    end

    @constraint(model, sum(x[s, j] for j in V if j != s) == 1)
    @constraint(model, sum(x[i, t] for i in V if i != t) == 1)
    @constraint(model, sum(x[i, s] for i in V if i != s) == 0)
    @constraint(model, sum(x[t, j] for j in V if j != t) == 0)

    for k in V
        if k != s && k != t
            @constraint(model, sum(x[i, k] for i in V if i != k) == 1)
            @constraint(model, sum(x[k, j] for j in V if j != k) == 1)
        end
    end

    @constraint(model, u[s] == 1)

    for i in V
        if i != s
            @constraint(model, u[i] >= 2)
            @constraint(model, u[i] <= n)
        end
    end

    for i in V, j in V
        if j != s && i != j
            @constraint(model, u[i] - u[j] + n * x[i, j] <= n - 1)
        end
    end

    tempo_exec = @elapsed optimize!(model)
    st = termination_status(model)
    tem_sol = (result_count(model) > 0)
    custo = tem_sol ? objective_value(model) : Inf

    arcos_solucao = Tuple{Int, Int}[]
    if tem_sol && !relaxacao
        for i in V, j in V
            if i != j && value(x[i, j]) > 0.5
                push!(arcos_solucao, (i, j))
            end
        end
    end

    return (status = st, custo = custo, tempo = tempo_exec, arcos = arcos_solucao)
end

function carregar_instancia_txt(caminho::String)
    if !isfile(caminho) || filesize(caminho) == 0
        error("Arquivo vazio ou inexistente.")
    end

    linhas = filter(!isempty, strip.(readlines(caminho)))
    if isempty(linhas)
        error("Arquivo sem conteudo legivel.")
    end

    n = tryparse(Int, linhas[1])
    if n === nothing || n < 2
        error("Numero de vertices invalido: $(linhas[1])")
    end

    if length(linhas) < n + 1
        error("Linhas insuficientes: esperado $(n + 1), lido $(length(linhas))")
    end

    C = zeros(Float64, n, n)
    for i in 1:n
        tokens = split(linhas[i + 1])
        if length(tokens) != n
            error("Linha $i tem $(length(tokens)) colunas (esperado $n)")
        end
        for j in 1:n
            val = tryparse(Float64, tokens[j])
            if val === nothing
                error("Caractere invalido em ($i, $j): $(tokens[j])")
            end
            if val < 0.0
                error("Custo negativo em ($i, $j): $val")
            end
            C[i, j] = val
        end
    end

    return n, C
end

function carregar_instancia_atsp(caminho::String)
    if !isfile(caminho) || filesize(caminho) == 0
        error("Arquivo vazio ou inexistente.")
    end

    linhas = readlines(caminho)
    n = 0
    valores_brutos = Float64[]
    na_secao_pesos = false

    for linha in linhas
        linha_limpa = strip(linha)
        if isempty(linha_limpa)
            continue
        end

        if startswith(uppercase(linha_limpa), "DIMENSION")
            partes = split(linha_limpa, ":")
            n = parse(Int, strip(partes[end]))
        elseif startswith(uppercase(linha_limpa), "EDGE_WEIGHT_SECTION")
            na_secao_pesos = true
            continue
        elseif startswith(uppercase(linha_limpa), "EOF") || startswith(uppercase(linha_limpa), "TOUR_SECTION")
            break
        end

        if na_secao_pesos
            dados_linha = split(linha_limpa)
            for val in dados_linha
                push!(valores_brutos, parse(Float64, val))
            end
        end
    end

    if n == 0 || length(valores_brutos) < n * n
        error("Formato atsp invalido ou pesos insuficientes.")
    end

    C = zeros(Float64, n, n)
    idx = 1
    for i in 1:n, j in 1:n
        C[i, j] = valores_brutos[idx]
        idx += 1
    end

    return n, C
end

function gerar_grafico_caminho(n::Int, arcos::Vector{Tuple{Int, Int}}, nome_instancia::String, pasta_saida::String)
    if isempty(arcos)
        return
    end

    if !isdir(pasta_saida)
        mkpath(pasta_saida)
    end

    gr()

    semente = hash(nome_instancia) % 10000
    Random.seed!(abs(semente))
    x_nos = rand(5.0:95.0, n)
    y_nos = rand(5.0:95.0, n)

    if occursin("simetrico_50", nome_instancia)
        Random.seed!(12)
        x_nos = rand(5.0:95.0, n)
        y_nos = rand(5.0:95.0, n)
    elseif occursin("assimetrico_50", nome_instancia)
        Random.seed!(34)
        x_nos = rand(5.0:95.0, n)
        y_nos = rand(5.0:95.0, n)
    end

    p = plot(
        title = "PCHM MTZ - $nome_instancia (n = $n)",
        titlefont = font(11, :bold),
        size = (1000, 800),
        grid = true,
        gridalpha = 0.15,
        background_color = :white,
        legend = :topright
    )

    adj = Dict(u => v for (u, v) in arcos)
    sequencia = [1]
    atual = 1
    while haskey(adj, atual) && length(sequencia) < n
        atual = adj[atual]
        push!(sequencia, atual)
    end

    gradiente = cgrad(:viridis, max(1, length(sequencia) - 1), categorical=true)

    if length(sequencia) > 1
        for idx in 1:(length(sequencia) - 1)
            u = sequencia[idx]
            v = sequencia[idx + 1]

            plot!([x_nos[u], x_nos[v]], [y_nos[u], y_nos[v]],
                  color = gradiente[idx],
                  linewidth = 2.0,
                  alpha = 0.85,
                  label = "")

            mx = (x_nos[u] + x_nos[v]) / 2.0
            my = (y_nos[u] + y_nos[v]) / 2.0
            scatter!([mx], [my],
                     marker = :utriangle,
                     markersize = 4,
                     color = gradiente[idx],
                     markerstrokewidth = 0,
                     label = "")
        end
    end

    scatter!(x_nos, y_nos,
             markersize = (n > 50 ? 5 : 7),
             color = :lightgrey,
             markerstrokecolor = :black,
             markerstrokewidth = 0.5,
             label = "Vertices")

    scatter!([x_nos[1]], [y_nos[1]],
             color = :lime,
             markersize = 12,
             marker = :square,
             label = "Origem (s=1)")

    scatter!([x_nos[n]], [y_nos[n]],
             color = :crimson,
             markersize = 12,
             marker = :star8,
             label = "Destino (t=$n)")

    if n <= 60
        for i in 1:n
            annotate!(x_nos[i], y_nos[i] + 2.0, text(string(i), :black, :center, :bold, 6))
        end
    end

    nome_png = replace(nome_instancia, r"\.(txt|atsp)$" => ".png")
    caminho_arquivo = joinpath(pasta_saida, nome_png)
    savefig(p, caminho_arquivo)
end

function processar_conjunto(diretorio::String, f_relatorio, f_csv, p_bar, pasta_graficos::String; extensao::String=".txt")
    if !isdir(diretorio)
        return
    end

    arquivos = sort(filter(f -> endswith(f, extensao), readdir(diretorio)))
    if isempty(arquivos)
        return
    end

    for arq in arquivos
        caminho = joinpath(diretorio, arq)

        try
            n, C = extensao == ".atsp" ? carregar_instancia_atsp(caminho) : carregar_instancia_txt(caminho)
            s = 1
            t = n

            res_lp = resolver_pchm_gurobi(n, C; s=s, t=t, relaxacao=true)
            res_ip = resolver_pchm_gurobi(n, C; s=s, t=t, relaxacao=false, time_limit_sec=180.0)

            valido = verificar_caminho_valido(n, res_ip.arcos, s, t)
            gap = (res_ip.custo != Inf && res_ip.custo > 0 && res_lp.custo != Inf) ?
                  ((res_ip.custo - res_lp.custo) / res_ip.custo) * 100.0 : 0.0

            caminho_ordenado = [s]
            mapa_arcos = Dict(u => v for (u, v) in res_ip.arcos)
            atual = s
            while haskey(mapa_arcos, atual) && length(caminho_ordenado) < n
                prox = mapa_arcos[atual]
                push!(caminho_ordenado, prox)
                atual = prox
            end

            linha = @sprintf("%-32s | %-4d | %9.2f | %5.2fs | %9.2f | %5.2fs | %6.2f%% | %-6s | %-10s",
                             arq, n, res_lp.custo, res_lp.tempo, res_ip.custo, res_ip.tempo, gap, string(valido), string(res_ip.status))
            println(linha)
            println(f_relatorio, linha)

            write(f_csv, "$arq;$n;$(res_lp.status);$(round(res_lp.custo, digits=2));$(round(res_lp.tempo, digits=4));$(res_ip.status);$(round(res_ip.custo, digits=2));$(round(res_ip.tempo, digits=4));$(round(gap, digits=2));$valido\n")

            if valido && length(caminho_ordenado) == n
                println(f_relatorio, "  Rota: ", join(caminho_ordenado, " -> "))
                gerar_grafico_caminho(n, res_ip.arcos, arq, pasta_graficos)
            end

        catch e
            msg_erro = replace(sprint(showerror, e), "\n" => " ")
            linha_erro = @sprintf("%-32s | %-4s | %-9s | %-6s | %-9s | %-6s | %-7s | %-6s | ERRO: %s",
                                  arq, "-", "-", "-", "-", "-", "-", "-", msg_erro)
            println(linha_erro)
            println(f_relatorio, linha_erro)
            write(f_csv, "$arq;0;ERROR;N/A;N/A;ERROR;N/A;N/A;N/A;false\n")
        end

        next!(p_bar)
    end
end

function main()
    hw = obter_info_hardware()
    saida_relatorio = "relatorio_pchm_gurobi.txt"
    saida_csv = "resultados_completos_pchm.csv"
    pasta_graficos = "graficos"

    pastas_txt = filter(isdir, ["instancias", "../instancias"])
    dir_txt = isempty(pastas_txt) ? "" : pastas_txt[1]

    pastas_atsp = filter(isdir, ["instancias-professor", "trab-01/instancias-professor", "../instancias-professor"])
    dir_atsp = isempty(pastas_atsp) ? "" : pastas_atsp[1]

    total_arquivos = 0
    if !isempty(dir_txt)
        total_arquivos += length(filter(f -> endswith(f, ".txt"), readdir(dir_txt)))
    end
    if !isempty(dir_atsp)
        total_arquivos += length(filter(f -> endswith(f, ".atsp"), readdir(dir_atsp)))
    end

    p_bar = Progress(total_arquivos, dt=0.5, desc="Processando: ", barlen=25)

    open(saida_relatorio, "w") do f_rel
        open(saida_csv, "w") do f_csv
            println(f_rel, "HARDWARE E AMBIENTE COMPUTACIONAL:")
            println(f_rel, "  Processador: ", hw.cpu)
            println(f_rel, "  Nucleos/Threads: ", hw.threads)
            println(f_rel, "  Memoria RAM: ", hw.ram)
            println(f_rel, "  Sistema Operacional: ", hw.so)
            println(f_rel, "  Versao Julia: ", hw.julia_v)
            println(f_rel, "  Solver: Gurobi Optimizer")
            println(f_rel, "")

            write(f_csv, "Instancia;N;Status_LP;Z_LP;Tempo_LP_s;Status_IP;Z_IP;Tempo_IP_s;GAP_Percentual;Caminho_Valido\n")

            println(@sprintf("%-32s | %-4s | %-9s | %-6s | %-9s | %-6s | %-7s | %-6s | %-10s",
                    "Instancia", "n", "Z_LP", "T_LP", "Z_IP", "T_IP", "GAP", "Valido", "Status"))

            if !isempty(dir_txt)
                processar_conjunto(dir_txt, f_rel, f_csv, p_bar, pasta_graficos; extensao=".txt")
            end

            if !isempty(dir_atsp)
                processar_conjunto(dir_atsp, f_rel, f_csv, p_bar, pasta_graficos; extensao=".atsp")
            end
        end
    end
end

main()