---
description: Roda os testes de regras do Godot e explica o resultado
---
Rode `powershell -ExecutionPolicy Bypass -File tools/rodar_testes.ps1 $ARGUMENTS`.
(Sem argumentos roda os 11 testes sem simulação; com `-ComSimulacao` roda as partidas de robôs; nomes de teste rodam só esses.)

Depois leia `tools/saida_testes/resumo.txt`. Para cada teste com 1, abra só o log dele em `tools/saida_testes/<teste>.txt`,
procure as linhas de FALHA/ERROR/SCRIPT ERROR e explique em português simples o que quebrou e qual arquivo provavelmente causa.
Não corrija nada sem eu pedir.
