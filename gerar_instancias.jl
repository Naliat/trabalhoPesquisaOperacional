using Random
using LinearAlgebra

function gerar_todos_os_cenarios(pasta::String)
    if !ispath(pasta)
        mkdir(pasta)
        println("📁 Pasta '$pasta' criada com sucesso.")
    end

    println("\n[ETAPA 1] Gerando instâncias euclidianas realistas...")

    # --- GRUPO A: CENÁRIOS VÁLIDOS GEOMÉTRICOS (50 NÓS) ---
    
    # 1. Cenário Padrão Válido Grande (Simétrico - 50 nós)
    open(joinpath(pasta, "01_valido_simetrico_50.txt"), "w") do io
        write(io, "50\n")
        Random.seed!(12)
        # Gera posições geográficas reais primeiro
        x = rand(5.0:95.0, 50)
        y = rand(5.0:95.0, 50)
        for i in 1:50
            linha = Float64[]
            for j in 1:50
                if i == j
                    push!(linha, 0.0)
                else
                    # O custo é a distância física real entre as cidades
                    dist = sqrt((x[i]-x[j])^2 + (y[i]-y[j])^2)
                    push!(linha, round(dist, digits=1))
                end
            end
            write(io, join(string.(linha), " ") * "\n")
        end
    end

    # 2. Cenário Válido Assimétrico Grande (50 nós)
    open(joinpath(pasta, "02_valido_assimetrico_50.txt"), "w") do io
        write(io, "50\n")
        Random.seed!(34)
        x = rand(5.0:95.0, 50)
        y = rand(5.0:95.0, 50)
        for i in 1:50
            linha = Float64[]
            for j in 1:50
                if i == j
                    push!(linha, 0.0)
                else
                    dist = sqrt((x[i]-x[j])^2 + (y[i]-y[j])^2)
                    # Adiciona penalidade assimétrica (ex: vento ou trânsito em um sentido)
                    fator_assimetrico = (i < j) ? 1.0 : 1.3
                    push!(linha, round(dist * fator_assimetrico, digits=1))
                end
            end
            write(io, join(string.(linha), " ") * "\n")
        end
    end

    # 3. Caso Limite Mínimo Válido (Apenas 2 nós)
    open(joinpath(pasta, "03_caso_limite_minimo_02.txt"), "w") do io
        write(io, "2\n0 15\n15 0\n")
    end

    # --- GRUPO B: ANOMALIAS ---
    open(joinpath(pasta, "04_anomalia_destino_isolado.txt"), "w") do io
        write(io, "4\n0 10 20 9999\n10 0 15 9999\n20 15 0 9999\n9999 9999 9999 0\n")
    end
    open(joinpath(pasta, "05_anomalia_custo_negativo.txt"), "w") do io
        write(io, "4\n0 10 -50 20\n10 0 15 30\n20 15 0 10\n15 30 10 0\n")
    end
    open(joinpath(pasta, "06_anomalia_subrota_obrigatoria.txt"), "w") do io
        write(io, "4\n0 9999 9999 25\n9999 0 10 9999\n9999 10 0 9999\n25 9999 9999 0\n")
    end

    # --- GRUPO C: ERROS DE FORMATAÇÃO ---
    open(joinpath(pasta, "07_erro_linhas_insuficientes.txt"), "w") do io
        write(io, "5\n0 10 20\n10 0 15\n20 15 0\n")
    end
    open(joinpath(pasta, "08_erro_matriz_nao_quadrada.txt"), "w") do io
        write(io, "3\n0 10 20 40 50\n10 0 15\n20 15 0\n")
    end
    open(joinpath(pasta, "09_erro_arquivo_vazio.txt"), "w") do io end
    open(joinpath(pasta, "10_erro_caractere_invalido.txt"), "w") do io
        write(io, "3\n0 CUSTO_ALTO 20\n10 0 ERRO\n20 15 0\n")
    end

    println("   ✔ Todos os 10 cenários geométricos gerados na pasta '$pasta'.")
end

gerar_todos_os_cenarios("instancias")
