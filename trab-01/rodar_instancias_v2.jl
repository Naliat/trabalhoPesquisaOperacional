# OBRIGATÓRIO PARA UBUNTU: Configura o driver NULL antes de carregar as bibliotecas gráficas
ENV["GKSwstype"] = "100" 

using JuMP
using GLPK
using LinearAlgebra
using DelimitedFiles
using Combinatorics
using Plots
using Random

# CORRIGIDO: Inclui explicitamente o novo arquivo v2 do resolvedor
include("pchm_solver_v2.jl")

# 2. LEITOR ROBUSTO DA TSPLIB (.ATSP) COM RECONSTRUTOR DE QUEBRAS DE LINHA
function ler_instancia_po(caminho_arquivo::String)
    linhas = readlines(caminho_arquivo)
    
    n = 0
    valores_brutos = Float64[]
    na_secao_pesos = false
    
    for linha in linhas
        linha_limpa = strip(linha)
        if isempty(linha_limpa) continue end
        
        if startswith(uppercase(linha_limpa), "DIMENSION")
            partes = split(linha_limpa, ":")
            n = parse(Int, strip(partes[2]))
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
    
    if n == 0 || isempty(valores_brutos)
        error("Formato inválido ou seção de pesos não encontrada no arquivo .atsp.")
    end
    
    matriz = zeros(Float64, n, n)
    idx = 1
    for i in 1:n
        for j in 1:n
            if idx <= length(valores_brutos)
                matriz[i, j] = valores_brutos[idx]
                idx += 1
            end
        end
    end
    return n, matriz
end

# INTERFACE GRÁFICA: MODELO DE MAPA ESPALHADO EM 2D (SISTEMA DE COORDENADAS REAIS)
function gerar_grafico_rota(n::Int, arcos_ativos::Vector{Tuple{Int,Int}}, nome_instancia::String, pasta_salvar::String)
    if !ispath(pasta_salvar) mkdir(pasta_salvar) end
    if isempty(arcos_ativos) return end 

    gr()

    # Semente estável baseada no nome do arquivo para manter os nós fixos no mapa
    semente = hash(nome_instancia) % 10000
    Random.seed!(abs(semente))
    x_nos = rand(5.0:95.0, n)
    y_nos = rand(5.0:95.0, n)
    
    p = plot(
        title = "Mapa Logístico Rastreável (N = $n)\nInstancia: $nome_instancia",
        titlefont = font(12, :bold),
        size = (1100, 850),
        grid = true,
        gridalpha = 0.1,
        background_color = :white
    )
    
    adj_dict = Dict(i => j for (i, j) in arcos_ativos)
    sequencia_caminho = Int[]
    atual = 1
    push!(sequencia_caminho, atual)
    while haskey(adj_dict, atual) && length(sequencia_caminho) < n
        atual = adj_dict[atual]
        push!(sequencia_caminho, atual)
    end

    cores_gradiente = cgrad(:viridis, max(1, length(sequencia_caminho)-1), categorical=true)
    
    if length(sequencia_caminho) > 1
        for idx in 1:(length(sequencia_caminho)-1)
            i = sequencia_caminho[idx]
            j = sequencia_caminho[idx+1]
            
            plot!([x_nos[i], x_nos[j]], [y_nos[i], y_nos[j]], 
                color = cores_gradiente[idx], 
                linewidth = 2.5, 
                alpha = 0.9,
                label = ""
            )
            
            mx, my = (x_nos[i] + x_nos[j])/2, (y_nos[i] + y_nos[j])/2
            scatter!([mx], [my], marker=:utriangle, markersize=5, color=cores_gradiente[idx], markerstrokewidth=0, label="")
        end
    end
    
    scatter!(x_nos, y_nos, markersize=6, color=:lightgrey, markerstrokecolor=:black, markerstrokewidth=0.5, label="Cidades do Percurso")
    scatter!([x_nos[1]], [y_nos[1]], color=:lime, markersize=14, marker=:square, label="⚡ INÍCIO (Cidade 1)")
    scatter!([x_nos[n]], [y_nos[n]], color=:crimson, markersize=14, marker=:star8, label="🏁 FIM (Cidade $n)")
    
    if n <= 60
        for i in 1:n
            annotate!(x_nos[i], y_nos[i] + 2.5, text(string(i), :black, :center, :bold, 6))
        end
    end
    
    nome_imagem = replace(nome_instancia, r"\.atsp$" => ".png")
    if !endswith(nome_imagem, ".png") nome_imagem *= ".png" end
    
    caminho_imagem = joinpath(pasta_salvar, nome_imagem)
    savefig(p, caminho_imagem)
    println("     [🖼️] MAPA LOGÍSTICO GERADO COM GRADIENTE: $caminho_imagem")
end

function executar_lote_total(pasta_instancias::String, arquivo_saida::String, pasta_graficos::String)
    println("\n[ETAPA 2] Processando os cenários da TSPLIB via JuMP + GLPK...")
    if !ispath(pasta_instancias)
        error("A pasta '$pasta_instancias' não existe no diretório.")
    end
    
    arquivos = sort(filter(f -> endswith(f, ".atsp"), readdir(pasta_instancias)))
    
    if isempty(arquivos)
        println("⚠️ Nenhum arquivo .atsp encontrado na pasta '$pasta_instancias'.")
        return
    end

    open(arquivo_saida, "w") do io
        write(io, "Instancia;Leitura_Status;Otimizacao_Status;Custo_Total;Caminho_Valido\n")
        for arq in arquivos
            caminho_completo = joinpath(pasta_instancias, arq)
            println("   " * "-"^76)
            println("   ▶ Analisando: $arq")
            leitura, otimizacao, custo, valido = "SUCESSO", "N/A", "N/A", "N/A"
            try
                n, Matriz_Custo = ler_instancia_po(caminho_completo)
                s, t = 1, n
                
                # Executa o lote com limite de 180s (3 minutos) por arquivo
                obj_int, arcos_int, status_solv = resolver_PCHM_MTZ(Matriz_Custo, inteiro=true, tempo_limite_seg=180)
                otimizacao = string(status_solv)
                
                if status_solv == OPTIMAL || status_solv == TIME_LIMIT
                    custo = string(round(obj_int, digits=2))
                    caminho_valido = verificar_caminho_valido(arcos_int, n, 1, n)
                    valido = string(caminho_valido)
                    println("     [✔] Concluido! Dimensão: $n | Custo = $custo | Rota Valida? = $valido")
                    gerar_grafico_rota(n, arcos_int, arq, pasta_graficos)
                else
                    println("     [⚠️] Solver parou: Motivo = $status_solv")
                end
            catch e
                leitura = "ERRO_FORMATO"
                println("     [❌] Bloqueado: ", sprint(showerror, e))
            end
            write(io, "$arq;$leitura;$otimizacao;$custo;$valido\n")
        end
    end
end

executar_lote_total("instancias-professor", "resultados_cenarios_completos.csv", "graficos")
println("\n[✔] PIPELINE FINALIZADO COM SUCESSO!")
